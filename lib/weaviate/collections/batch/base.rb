# frozen_string_literal: true

require_relative "helpers"
require_relative "grpc_batch"
require_relative "rest"

module Weaviate
  module Collections
    module Batch
      # Minimal logger used by the batching code (Python: logging.getLogger("weaviate-client"), whose default
      # last-resort handler prints WARNING and above to stderr). Replace it with any Logger-compatible object
      # via `Weaviate::Collections::Batch.logger = Logger.new(...)`.
      class BatchLogger
        LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

        attr_accessor :level, :io

        def initialize(io = $stderr, level: :warn)
          @io = io
          @level = level
        end

        LEVELS.each_key do |name|
          define_method(name) do |message = nil|
            next if LEVELS.fetch(name) < LEVELS.fetch(level)

            io.puts("[weaviate-client] #{name.upcase}: #{message.is_a?(String) ? message : message.inspect}")
          end
        end
      end

      class << self
        attr_writer :logger

        def logger
          @logger ||= BatchLogger.new
        end
      end

      MAX_CONCURRENT_REQUESTS = 10
      CONCURRENT_REQUESTS_DYNAMIC_VECTORIZER = 2
      BATCH_TIME_TARGET = 10
      VECTORIZER_BATCHING_STEP_SIZE = 48 # cohere max batch size is 96
      # approximately 10m30s of waiting in worst case, e.g. server scale up event
      MAX_RETRIES = Float(ENV.fetch("WEAVIATE_BATCH_MAX_RETRIES", "9.299"))
      GCP_STREAM_TIMEOUT = 160 # GCP connections have a max lifetime of 180s, leave 20s of buffer as safety

      def self.now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # Port of BatchRequest: a thread-safe list of pending items.
      class BatchRequest
        def initialize
          @items = []
          @lock = Mutex.new
        end

        def length = @lock.synchronize { @items.length }
        alias size length

        def add(item)
          @lock.synchronize { @items << item }
        end

        # Add items to the front (used when objects should be retried, e.g. after a temporary error).
        def prepend(items)
          @lock.synchronize { @items = items + @items }
        end

        def head = @lock.synchronize { @items.first }
      end

      # Collect Weaviate-object references to add them in one request to Weaviate.
      class ReferencesBatchRequest < BatchRequest
        def pop_items(pop_amount, uuid_lookup:)
          @lock.synchronize do
            ret = []
            i = 0
            while ret.length < pop_amount && !@items.empty? && i < @items.length
              item = @items[i]
              if !uuid_lookup.include?(item.from_object_uuid) &&
                 (item.to_object_uuid.nil? || !uuid_lookup.include?(item.to_object_uuid))
                ret << @items.delete_at(i)
              else
                i += 1
              end
            end
            ret
          end
        end
      end

      # Collect objects for one batch request to Weaviate.
      class ObjectsBatchRequest < BatchRequest
        def pop_items(pop_amount)
          @lock.synchronize { @items.shift(pop_amount) }
        end
      end

      # Port of _BatchStreamRequest
      BatchStreamRequest = Struct.new(:proto, :uuids, :beacons)

      # Port of _BatchDataWrapper: results shared between a batch and its wrapper.
      class BatchDataWrapper
        attr_accessor :results, :failed_objects, :failed_references, :imported_shards

        def initialize
          @results = ::Weaviate::Outputs::Batch::BatchResult.new
          @failed_objects = []
          @failed_references = []
          @imported_shards = Set.new
        end
      end

      # Batching modes (Python _DynamicBatching, _FixedSizeBatching, _RateLimitedBatching, _ServerSideBatching).
      class DynamicBatching < ::Weaviate::Model; end

      class FixedSizeBatching < ::Weaviate::Model
        attribute :batch_size
        attribute :concurrent_requests
      end

      class RateLimitedBatching < ::Weaviate::Model
        attribute :requests_per_minute

        def after_initialize
          return if requests_per_minute.is_a?(Integer) && requests_per_minute >= 1

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "requests_per_minute must be a positive integer, got #{requests_per_minute}"
        end

        def get_sleep_time(number_objects:, elapsed_time:, base_time:)
          batch_interval = base_time.to_f * number_objects / requests_per_minute
          [batch_interval - elapsed_time, 0].max
        end
      end

      class ServerSideBatching < ::Weaviate::Model
        attribute :concurrency
      end

      # Port of _ClusterBatch
      class ClusterBatch
        def initialize(connection)
          @connection = connection
        end

        def get_nodes_status
          response = begin
            @connection.get("/nodes")
          rescue StandardError
            return []
          end
          response_typed = ::Weaviate::Util.decode_json_response_dict(response, "Nodes status")
          response_typed["nodes"] || []
        end

        def get_number_of_nodes = get_nodes_status.length
      end

      # Port of _BgThreads: the loop + recv threads of a server-side batch.
      class BgThreads
        attr_reader :loop, :recv

        def initialize(loop:, recv:)
          @loop = loop # lambdas creating the threads lazily
          @recv = recv
          @loop_thread = nil
          @recv_thread = nil
        end

        def start_recv
          @recv_thread ||= @recv.call
        end

        def start_loop
          @loop_thread ||= @loop.call
        end

        def is_alive = loop_alive && recv_alive # rubocop:disable Naming/PredicatePrefix
        alias alive? is_alive

        def loop_alive = @loop_thread.nil? || @loop_thread.alive?
        def recv_alive = @recv_thread.nil? || @recv_thread.alive?

        def join(timeout = nil)
          deadline = timeout.nil? ? nil : Batch.now + timeout
          [@loop_thread, @recv_thread].compact.each do |t|
            t.join(deadline.nil? ? nil : [deadline - Batch.now, 0].max)
          end
        end
      end

      # Port of _BatchBase: client-side batching (dynamic / fixed size / rate limited) with background
      # threads that send objects over gRPC and references over REST.
      class BatchBase
        def initialize(connection:, consistency_level:, results:, batch_mode:, executor: nil, vectorizer_batching: false,
                       objects: nil, references: nil)
          @batch_objects = objects || ObjectsBatchRequest.new
          @batch_references = references || ReferencesBatchRequest.new

          @connection = connection
          @consistency_level = consistency_level
          @vectorizer_batching = vectorizer_batching

          @batch_grpc = BatchGRPC.for_connection(connection, consistency_level)
          @batch_rest = BatchREST.new(consistency_level)

          # lookup table for objects that are currently being processed - used to not send references from
          # objects that have not been added yet
          @uuid_lookup = Set.new

          # users must not access the results directly as they are not thread-safe
          @results_for_wrapper_backup = results
          @results_for_wrapper = BatchDataWrapper.new

          @cluster = ClusterBatch.new(connection)

          @batching_mode = batch_mode
          @max_batch_size = 1000

          @executor = executor
          @objs_count = 0
          @refs_count = 0
          @objs_logs_count = 0
          @refs_logs_count = 0
          @batch_send_flag = false
          @dynamic_batching_sleep_time = 0

          case @batching_mode
          when FixedSizeBatching
            @recommended_num_objects = @batching_mode.batch_size
            @concurrent_requests = @batching_mode.concurrent_requests
          when RateLimitedBatching
            # Never send more than the given amount of objects per minute: send multiple batches of equal size
            # (at most @max_batch_size) equally spaced in time.
            @concurrent_requests = (@batching_mode.requests_per_minute + @max_batch_size) / @max_batch_size
            @recommended_num_objects = @batching_mode.requests_per_minute / @concurrent_requests
          else
            if @vectorizer_batching
              @recommended_num_objects = VECTORIZER_BATCHING_STEP_SIZE
            else
              @recommended_num_objects = 10
            end
            @concurrent_requests = 2
          end

          @recommended_num_refs = 50
          @active_requests = 0

          # dynamic batching
          @time_last_scale_up = 0
          @rate_queue = [] # maxlen 50
          @took_queue = [] # maxlen CONCURRENT_REQUESTS_DYNAMIC_VECTORIZER

          # fixed rate batching
          @time_stamp_last_request = 0
          @num_objects_in_previous_batch = 0
          # 62 secs to give us some buffer to the "per-minute" calculation
          @fix_rate_batching_base_time = 62

          @active_requests_lock = Mutex.new
          @uuid_lookup_lock = Mutex.new
          @results_lock = Mutex.new

          @bg_thread_exception = nil
          @bg_threads = start_bg_threads
        end

        def number_errors
          @results_for_wrapper.failed_objects.length + @results_for_wrapper.failed_references.length
        end

        def _start; end

        def _wait; end

        # Shutdown the current batch and wait for all requests to be finished.
        def _shutdown
          flush

          # we are done, shut the bg threads down
          @shut_background_thread_down = true
          sleep(0.01) while @bg_threads.alive?

          # copy the results to the public results
          @results_for_wrapper_backup.results = @results_for_wrapper.results
          @results_for_wrapper_backup.failed_objects = @results_for_wrapper.failed_objects
          @results_for_wrapper_backup.failed_references = @results_for_wrapper.failed_references
          @results_for_wrapper_backup.imported_shards = @results_for_wrapper.imported_shards
        end

        # Flush the batch queue and wait for all requests to be finished.
        def flush
          while @active_requests.positive? || @batch_objects.length.positive? || @batch_references.length.positive?
            sleep(0.01)
            check_bg_threads_alive
          end
        end

        def _add_object(collection:, properties: nil, references: nil, uuid: nil, vector: nil, tenant: nil)
          check_bg_threads_alive
          begin
            batch_object = ::Weaviate::Classes::Batch::BatchObject.new(
              collection: collection, properties: properties, references: references, uuid: uuid,
              vector: vector, tenant: tenant, index: @objs_count
            )
            @objs_count += 1
            @results_for_wrapper.imported_shards.add(::Weaviate::Classes::Batch::Shard.new(collection: collection,
                                                                                           tenant: tenant))
          rescue ::Weaviate::Classes::Batch::ValidationError => e
            raise ::Weaviate::Exceptions::WeaviateBatchValidationError, e.inspect
          end
          @uuid_lookup_lock.synchronize { @uuid_lookup.add(batch_object.uuid.to_s) }
          @batch_objects.add(batch_object)

          # block if queue gets too long or weaviate is overloaded - reading files is faster than sending them
          # so we do not need a long queue
          while @recommended_num_objects.zero? || @batch_objects.length >= @recommended_num_objects * 2
            check_bg_threads_alive
            sleep(0.01)
          end

          batch_object.uuid
        end

        def _add_reference(from_object_uuid:, from_object_collection:, from_property_name:, to:, tenant: nil)
          check_bg_threads_alive
          multi = Helpers.reference_to_multi?(to)
          to_strs =
            if multi
              Helpers.reference_uuids_str(to)
            elsif to.is_a?(String)
              [to]
            else
              to.to_a
            end

          to_strs.each do |uid|
            begin
              batch_reference = ::Weaviate::Classes::Batch::BatchReference.new(
                from_object_collection: from_object_collection, from_object_uuid: from_object_uuid,
                from_property_name: from_property_name, to_object_collection: (to.target_collection if multi),
                to_object_uuid: uid, tenant: tenant, index: @refs_count
              )
              @refs_count += 1
            rescue ::Weaviate::Classes::Batch::ValidationError => e
              raise ::Weaviate::Exceptions::WeaviateBatchValidationError, e.inspect
            end
            @batch_references.add(batch_reference)
          end

          # block if weaviate is overloaded, also do not send any refs
          while @recommended_num_objects.zero?
            sleep(0.01)
            check_bg_threads_alive
          end
        end

        private

        def logger = Batch.logger

        def shutting_down? = @shut_background_thread_down == true

        def batch_send_loop
          refresh_time = 0.01
          until shutting_down?
            if @batching_mode.is_a?(RateLimitedBatching)
              sleep_time = @batching_mode.get_sleep_time(
                number_objects: @num_objects_in_previous_batch,
                elapsed_time: Batch.now - @time_stamp_last_request,
                base_time: @fix_rate_batching_base_time
              )
              if sleep_time.positive?
                sleep([sleep_time, 1].min)
                next
              end
              refresh_time = 0
            elsif @batching_mode.is_a?(DynamicBatching) && @vectorizer_batching &&
                  @dynamic_batching_sleep_time.positive? &&
                  Batch.now - @time_stamp_last_request < @dynamic_batching_sleep_time
              sleep(1)
              next
            end

            if @active_requests < @concurrent_requests && (@batch_objects.length + @batch_references.length).positive?
              @time_stamp_last_request = Batch.now unless @batching_mode.is_a?(RateLimitedBatching)

              @batch_send_flag = true
              @active_requests_lock.synchronize { @active_requests += 1 }

              start = Batch.now
              loop do
                len_o = @batch_objects.length
                len_r = @batch_references.length
                break unless len_o < @recommended_num_objects && len_r < @recommended_num_refs

                # wait for more objects to be added up to the recommended number
                sleep(0.01)
                break if shutting_down? # shutdown was requested, exit the loop
                # no new objects were added in the last second, exit the loop
                break if Batch.now - start >= 1 && len_o == @batch_objects.length && len_r == @batch_references.length
              end

              objs = @batch_objects.pop_items(@recommended_num_objects)
              refs = @uuid_lookup_lock.synchronize do
                @batch_references.pop_items(@recommended_num_refs, uuid_lookup: @uuid_lookup)
              end
              if @batching_mode.is_a?(RateLimitedBatching)
                # Preserve a future timestamp set by a concurrent rate-limit retry.
                @time_stamp_last_request = [@time_stamp_last_request, Batch.now].max
                @num_objects_in_previous_batch = objs.length
              end
              # do not block the thread - the results are written to a central (locked) list and we want to have
              # multiple concurrent batch-requests
              readd_rate_limit = @batching_mode.is_a?(RateLimitedBatching)
              t = Thread.new { send_batch(objs, refs, readd_rate_limit: readd_rate_limit) }
              t.report_on_exception = false
              t.name = "BgBatchSend"
            end

            sleep(refresh_time)
          end
        end

        def dynamic_batch_rate_loop
          refresh_time = 1
          until shutting_down?
            return unless @batching_mode.is_a?(DynamicBatching)

            begin
              dynamic_batching
            rescue StandardError => e
              logger.debug(e.inspect)
            end

            # sleep in small steps so that shutdown is not delayed by a full second
            deadline = Batch.now + refresh_time
            sleep(0.05) while Batch.now < deadline && !shutting_down?
          end
        end

        # Create the background threads that send batches and periodically check how congested the
        # server-side batch queue is.
        def start_bg_threads
          @shut_background_thread_down = false

          dynamic = Thread.new do
            Thread.current.name = "BgDynamicBatchRate"
            dynamic_batch_rate_loop
          rescue StandardError => e
            @bg_thread_exception = e
          end
          dynamic.report_on_exception = false

          sender = Thread.new do
            Thread.current.name = "BgBatchScheduler"
            batch_send_loop
          rescue StandardError => e
            logger.error(e)
            @bg_thread_exception = e
          end
          sender.report_on_exception = false
          sender
        end

        def push_bounded(queue, value, maxlen)
          queue << value
          queue.shift while queue.length > maxlen
        end

        def dynamic_batching
          status = @cluster.get_nodes_status
          if status.empty? || !status[0].key?("batchStats") || !status[0]["batchStats"].key?("queueLength")
            raise IndexError, "list index out of range" if status.empty?

            # async indexing - just send a lot
            @batching_mode = FixedSizeBatching.new(batch_size: 1000, concurrent_requests: 10)
            @recommended_num_objects = 1000
            @concurrent_requests = 10
            return
          end

          rate = status[0]["batchStats"]["ratePerSecond"]
          raise ZeroDivisionError, "division by zero" if @concurrent_requests.zero?

          rate_per_worker = rate.to_f / @concurrent_requests
          batch_length = status[0]["batchStats"]["queueLength"]

          push_bounded(@rate_queue, rate, 50)

          if @vectorizer_batching
            dynamic_batching_vectorizer
          elsif batch_length.zero? # scale up if queue is empty
            @recommended_num_objects = [@recommended_num_objects + 50, @max_batch_size].min

            if @max_batch_size == @recommended_num_objects &&
               @batch_objects.length > @recommended_num_objects &&
               Batch.now - @time_last_scale_up > 1 &&
               @concurrent_requests < MAX_CONCURRENT_REQUESTS
              @concurrent_requests += 1
              @time_last_scale_up = Batch.now
            end
          else
            raise ZeroDivisionError, "division by zero" if rate.zero?

            ratio = batch_length.to_f / rate
            if ratio < 2.1 && ratio > 1.9 # ideal, send exactly as many objects as weaviate can process
              @recommended_num_objects = rate_per_worker.floor
            elsif ratio <= 1.9 # we can send more
              @recommended_num_objects = [@recommended_num_objects * 1.5, rate_per_worker * 2 / ratio].min.floor
              @concurrent_requests += 1 if @max_batch_size == @recommended_num_objects
            elsif ratio < 10 # too high, scale down
              @recommended_num_objects = (rate_per_worker * 2 / ratio).floor
              @concurrent_requests -= 1 if @recommended_num_objects < 100 && @concurrent_requests > 2
            else # way too high, stop sending new batches
              @recommended_num_objects = 0
              @concurrent_requests = 2
            end
          end
        end

        # slow vectorizer: send larger batches that can take a bit longer, but fewer of them. Might need to sleep.
        def dynamic_batching_vectorizer
          return unless !@took_queue.empty? && @batch_send_flag

          max_took = @took_queue.max
          @dynamic_batching_sleep_time = 0
          if max_took > 2 * BATCH_TIME_TARGET
            @concurrent_requests = 1
            @recommended_num_objects = VECTORIZER_BATCHING_STEP_SIZE
          elsif max_took > BATCH_TIME_TARGET
            current_step = @recommended_num_objects / VECTORIZER_BATCHING_STEP_SIZE
            if @concurrent_requests > 1
              @concurrent_requests -= 1
            elsif current_step > 1
              @recommended_num_objects = VECTORIZER_BATCHING_STEP_SIZE * (current_step - 1)
            else
              # cannot scale down, sleep a bit
              @dynamic_batching_sleep_time = max_took - BATCH_TIME_TARGET
            end
          elsif max_took < 3 * BATCH_TIME_TARGET / 4
            if @dynamic_batching_sleep_time.positive?
              @dynamic_batching_sleep_time = 0
            elsif @concurrent_requests < 3
              @concurrent_requests += 1
            else
              current_step = @recommended_num_objects / VECTORIZER_BATCHING_STEP_SIZE
              @recommended_num_objects = VECTORIZER_BATCHING_STEP_SIZE * (current_step + 1)
            end
          end
          @batch_send_flag = false
        end

        RATE_LIMIT_CHECKS = [
          ->(m) { m.include?("support@cohere.com") && (m.include?("rate limit") || m.include?("500 error: internal server error")) },
          lambda { |m|
            m.include?("OpenAI") && (m.include?("Rate limit reached") || m.include?("on tokens per min (TPM)") ||
                                     m.include?("503 error: Service Unavailable.") ||
                                     m.include?("500 error: The server had an error while processing your request."))
          },
          ->(m) { m.include?("failed with status: 503 error") } # huggingface
        ].freeze

        def send_batch(objs, refs, readd_rate_limit:)
          send_objects(objs, readd_rate_limit) unless objs.empty?
          send_references(refs) unless refs.empty?
        ensure
          @active_requests_lock.synchronize { @active_requests -= 1 }
        end

        def send_objects(objs, readd_rate_limit)
          n_objs = objs.length
          start = Batch.now
          begin
            response_obj = @batch_grpc.objects(@connection, objects: objs.map(&:to_internal),
                                                            timeout: @connection.timeout_config.insert,
                                                            max_retries: MAX_RETRIES)
            if response_obj.has_errors
              logger.error({ "message" => "Failed to send #{response_obj.errors.length} in a batch of #{n_objs}",
                             "errors" => response_obj.errors.values.map(&:message).uniq })
            end
          rescue StandardError => e
            errors_obj = objs.each_with_index.to_h do |obj, idx|
              [idx, ::Weaviate::Outputs::Batch::ErrorObject.new(message: Helpers.exception_repr(e), object_: obj)]
            end
            logger.error({ "message" => "Failed to send all objects in a batch of #{n_objs}",
                           "error" => Helpers.exception_repr(e) })
            response_obj = ::Weaviate::Outputs::Batch::BatchObjectReturn.new(
              _all_responses: errors_obj.values, elapsed_seconds: Batch.now - start, errors: errors_obj,
              has_errors: true
            )
          end

          readded_uuids = Set.new
          readded_objects = []
          highest_retry_count = 0
          response_obj.errors.each do |i, err|
            next unless RATE_LIMIT_CHECKS.any? { |check| check.call(err.message) }

            highest_retry_count = err.object_.retry_count if err.object_.retry_count > highest_retry_count
            next if err.object_.retry_count > 5 # too many retries, give up

            err.object_.retry_count += 1
            readded_objects << i
          end

          unless readded_objects.empty?
            ::Weaviate::Warnings.batch_rate_limit_reached(
              response_obj.errors[readded_objects[0]].message,
              @fix_rate_batching_base_time * (highest_retry_count + 1)
            )
            readd_objects = response_obj.errors.filter_map { |i, err| err.object_ if readded_objects.include?(i) }
            readded_uuids = readd_objects.to_set(&:uuid)
            @batch_objects.prepend(readd_objects)

            new_errors = response_obj.errors.reject { |i, _| readded_objects.include?(i) }
            response_obj = ::Weaviate::Outputs::Batch::BatchObjectReturn.new(
              uuids: response_obj.uuids.reject { |i, _| readded_objects.include?(i) },
              errors: new_errors,
              has_errors: !new_errors.empty?,
              _all_responses: response_obj._all_responses.each_with_index.reject { |_, i| readded_objects.include?(i) }
                                                         .map(&:first),
              elapsed_seconds: response_obj.elapsed_seconds
            )
            if readd_rate_limit
              # for rate limited batching the timing is handled by the outer loop => no sleep here
              @time_stamp_last_request = Batch.now + (@fix_rate_batching_base_time * (highest_retry_count + 1))
              @fix_rate_batching_base_time += 1 # increase the base time as the current one is too low
            else
              # sleep a bit to recover from the rate limit in other cases
              sleep(2**highest_retry_count)
            end
          end
          @uuid_lookup_lock.synchronize do
            objs.each { |obj| @uuid_lookup.delete(obj.uuid.to_s) unless readded_uuids.include?(obj.uuid) }
          end

          n_obj_errs = response_obj.errors.length
          if n_obj_errs.positive? && @objs_logs_count < 30
            logger.error({ "message" => "Failed to send #{n_obj_errs} objects in a batch of #{n_objs}. Please inspect " \
                                        "client.batch.failed_objects or collection.batch.failed_objects for the failed objects." })
            @objs_logs_count += 1
          end
          if @objs_logs_count > 30
            logger.error({ "message" => "There have been more than 30 failed object batches. Further errors will not be logged." })
          end
          @results_lock.synchronize do
            @results_for_wrapper.results.objs += response_obj
            @results_for_wrapper.failed_objects.concat(response_obj.errors.values)
            push_bounded(@took_queue, Batch.now - start, CONCURRENT_REQUESTS_DYNAMIC_VECTORIZER)
          end
        end

        def send_references(refs)
          n_refs = refs.length
          start = Batch.now
          begin
            response_ref = @batch_rest.references(@connection, references: refs.map(&:to_internal))
          rescue StandardError => e
            errors_ref = refs.each_with_index.to_h do |ref, idx|
              [idx, ::Weaviate::Outputs::Batch::ErrorReference.new(message: Helpers.exception_repr(e), reference: ref)]
            end
            response_ref = ::Weaviate::Outputs::Batch::BatchReferenceReturn.new(
              elapsed_seconds: Batch.now - start, errors: errors_ref, has_errors: true
            )
          end
          n_ref_errs = response_ref.errors.length
          if n_ref_errs.positive? && @refs_logs_count < 30
            logger.error({ "message" => "Failed to send #{n_ref_errs} references in a batch of #{n_refs}. Please inspect " \
                                        "client.batch.failed_references or collection.batch.failed_references for the " \
                                        "failed references.",
                           "errors" => response_ref.errors })
            @refs_logs_count += 1
          end
          if @refs_logs_count > 30
            logger.error({ "message" => "There have been more than 30 failed reference batches. Further errors will not be logged." })
          end
          @results_lock.synchronize do
            @results_for_wrapper.results.refs += response_ref
            @results_for_wrapper.failed_references.concat(response_ref.errors.values)
          end
        end

        def check_bg_threads_alive
          return if @bg_threads.alive?

          raise @bg_thread_exception || RuntimeError.new("Batch thread died unexpectedly")
        end
      end
    end
  end
end
