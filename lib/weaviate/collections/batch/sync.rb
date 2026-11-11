# frozen_string_literal: true

require_relative "base"

module Weaviate
  module Collections
    module Batch
      # Minimal port of threading.Event.
      class Event
        def initialize
          @set = false
        end

        def set = (@set = true)
        def clear = (@set = false)
        def is_set = @set # rubocop:disable Naming/PredicatePrefix
        alias set? is_set
      end

      # Port of weaviate.collections.batch.sync._BatchBaseSync: server-side batching over the bidirectional
      # BatchStream gRPC call (Weaviate >= 1.36).
      class BatchBaseSync
        def initialize(connection:, consistency_level:, results:, batch_mode: nil, executor: nil,
                       vectorizer_batching: false, objects: nil, references: nil)
          @batch_objects = objects || ObjectsBatchRequest.new
          @batch_references = references || ReferencesBatchRequest.new

          @connection = connection
          @is_gcp_on_wcd = connection.connection_params.is_gcp_on_wcd
          @is_renewing_stream = Event.new
          @consistency_level = consistency_level || "QUORUM"
          @batch_size = 100

          @batch_grpc = BatchGRPC.for_connection(connection, @consistency_level)
          @cluster = ClusterBatch.new(connection)
          @number_of_nodes = @cluster.get_number_of_nodes

          # lookup table for objects that are currently being processed - used to not send references from
          # objects that have not been added yet
          @uuid_lookup = Set.new

          # users must not access the results directly as they are not thread-safe
          @results_for_wrapper_backup = results
          @results_for_wrapper = BatchDataWrapper.new

          @objs_count = 0
          @refs_count = 0

          @uuid_lookup_lock = Mutex.new
          @results_lock = Mutex.new

          @bg_exception = nil
          @is_oom = Event.new
          @is_shutting_down = Event.new
          @is_hungup = Event.new
          @is_stopped = Event.new
          @oom_wait_time = 300

          @shutdown_loop = Event.new

          @objs_cache_lock = Mutex.new
          @refs_cache_lock = Mutex.new
          @objs_cache = {}
          @refs_cache = {}

          @acks_lock = Mutex.new
          @inflight_objs = Set.new
          @inflight_refs = Set.new

          # max 1 so that the loop does not run faster than the request enumerator of the stream
          @reqs = SizedQueue.new(1)
          # requests popped by the enumerator of a stream that has since been replaced; re-sent first by the
          # next stream (the Ruby gRPC writer thread may outlive its call)
          @stream_generation = 0
          @stale_reqs = []
          @stale_lock = Mutex.new
          @bg_threads = nil
        end

        def number_errors
          @results_for_wrapper.failed_objects.length + @results_for_wrapper.failed_references.length
        end

        def _start
          start_bg_threads
          logger.info("Provisioned stream to the server for batch processing")
          now = Batch.now
          until all_threads_alive?
            # wait for the recv threads to be started
            sleep(0.01)
            if Batch.now - now > 60
              raise ::Weaviate::Exceptions::WeaviateBatchStreamError,
                    "Batch stream was not started within 60 seconds. Please check your connection."
            end
          end
        end

        def _wait
          # this is how long an insert will take to timeout for, so we wait at most this time +5s for the batch
          # to finish after shutdown is initiated, in case the server never hangs up
          @bg_threads.join(@connection.timeout_config.insert + 5)

          # copy the results to the public results
          @results_for_wrapper_backup.results = @results_for_wrapper.results
          @results_for_wrapper_backup.failed_objects = @results_for_wrapper.failed_objects
          @results_for_wrapper_backup.failed_references = @results_for_wrapper.failed_references
          @results_for_wrapper_backup.imported_shards = @results_for_wrapper.imported_shards
        end

        # Shutdown the current batch and wait for all requests to be finished.
        def _shutdown
          @is_stopped.set
        end

        # Flush the batch queue and wait for all requests to be finished.
        def flush
          while @batch_objects.length.positive? || @batch_references.length.positive?
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
            @results_for_wrapper.imported_shards.add(::Weaviate::Classes::Batch::Shard.new(collection: collection,
                                                                                           tenant: tenant))
          rescue ::Weaviate::Classes::Batch::ValidationError => e
            raise ::Weaviate::Exceptions::WeaviateBatchValidationError, e.inspect
          end
          uuid = batch_object.uuid.to_s
          @uuid_lookup_lock.synchronize { @uuid_lookup.add(uuid) }
          @batch_objects.add(batch_object)
          @objs_cache_lock.synchronize { @objs_cache[uuid] = batch_object }
          @objs_count += 1

          while blocked?
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
            rescue ::Weaviate::Classes::Batch::ValidationError => e
              raise ::Weaviate::Exceptions::WeaviateBatchValidationError, e.inspect
            end
            @batch_references.add(batch_reference)
            @refs_cache_lock.synchronize do
              @refs_cache[batch_reference.to_beacon] = batch_reference
              @refs_count += 1
            end
            while blocked?
              logger.warn("Batch is blocked, waiting to add more references...")
              check_bg_threads_alive
              sleep(0.01)
            end
          end
        end

        private

        def logger = Batch.logger

        def all_threads_alive? = @bg_threads.alive?

        def put(req)
          loop do
            return true if @reqs.push([req], timeout: 1)
            return false if !@bg_exception.nil? || @shutdown_loop.set?
          end
        end

        def paused?
          @is_shutting_down.set? || @is_oom.set? || @is_hungup.set?
        end

        def batch_loop
          refresh_time = 0.01
          while @bg_exception.nil? && !@shutdown_loop.set?
            if (@batch_objects.length + @batch_references.length).positive?
              start = Batch.now
              loop do
                len_o = @batch_objects.length
                len_r = @batch_references.length
                break unless len_o + len_r < @batch_size

                # wait for more objects to be added up to the batch size
                sleep(refresh_time)
                # no new objects were added in the last second, exit the loop
                break if Batch.now - start >= 1 && len_o == @batch_objects.length && len_r == @batch_references.length
              end

              objs = @batch_objects.pop_items(@batch_size)
              refs = @uuid_lookup_lock.synchronize do
                @batch_references.pop_items(@batch_size - objs.length, uuid_lookup: @uuid_lookup)
              end

              generate_stream_requests(objs, refs) do |req|
                start = Batch.now
                paused = false
                while paused?
                  unless paused
                    logger.info("Server is shutting down, pausing batching loop...")
                    paused = true
                  end
                  sleep(refresh_time)
                  next unless Batch.now - start > @oom_wait_time

                  raise ::Weaviate::Exceptions::WeaviateBatchFailedToReestablishStreamError,
                        "Batch stream was not re-established within #{@oom_wait_time} seconds after an OOM " \
                        "message. Terminating batch."
                end
                logger.info("Server is back up, resuming batching loop...") if paused
                unless put(req)
                  logger.info("Batch loop is shutting down, stopping putting requests...")
                  return
                end
              end
            elsif @is_stopped.set? && !@is_hungup.set? && !@is_shutting_down.set? && !@is_oom.set?
              put(nil)
              logger.info("Sent sentinel, stopping batch loop...")
              return
            end
            sleep(refresh_time)
          end
        end

        def generate_stream_requests(objects, references)
          per_object_overhead = 4 # extra overhead bytes per object in the request
          max_size = @batch_grpc.grpc_max_msg_size

          new_request = lambda do
            ::Weaviate::V1::BatchStreamRequest.new(
              data: ::Weaviate::V1::BatchStreamRequest::Data.new(
                objects: ::Weaviate::V1::BatchStreamRequest::Data::Objects.new,
                references: ::Weaviate::V1::BatchStreamRequest::Data::References.new
              )
            )
          end
          request = new_request.call
          total_size = 0
          uuids = Set.new
          beacons = Set.new

          objects.each do |object_|
            obj = @batch_grpc.grpc_object(object_.to_internal)
            obj_size = obj.to_proto.bytesize + per_object_overhead

            if obj_size > max_size
              raise ::Weaviate::Exceptions::WeaviateBatchValidationError,
                    "Object with uuid #{object_.uuid} is too large to be sent in a batch request. Size: #{obj_size} " \
                    "bytes, max size: #{max_size} bytes."
            end

            if total_size + obj_size >= max_size
              yield BatchStreamRequest.new(request, uuids, beacons)
              request = new_request.call
              total_size = 0
              uuids = Set.new
              beacons = Set.new
            end

            request.data.objects.values << obj
            total_size += obj_size
            uuids.add(obj.uuid)
          end

          references.each do |reference|
            ref = @batch_grpc.grpc_reference(reference.to_internal)
            ref_size = ref.to_proto.bytesize + per_object_overhead

            if total_size + ref_size >= max_size
              yield BatchStreamRequest.new(request, uuids, beacons)
              request = new_request.call
              total_size = 0
              uuids = Set.new
              beacons = Set.new
            end

            request.data.references.values << ref
            total_size += ref_size
            beacons.add(reference.to_beacon)
          end

          return unless request.data.objects.values.length.positive? || request.data.references.values.length.positive?

          yield BatchStreamRequest.new(request, uuids, beacons)
        end

        # Python __send: the request generator of the stream (iterated by the gRPC writer thread).
        def send_enum(generation)
          Enumerator.new do |y|
            y << ::Weaviate::V1::BatchStreamRequest.new(
              start: ::Weaviate::V1::BatchStreamRequest::Start.new(consistency_level: @batch_grpc.consistency_level)
            )
            stream_start = Batch.now
            catch(:done) do
              while @bg_exception.nil?
                throw :done if generation != @stream_generation

                if @is_gcp_on_wcd && Batch.now - stream_start > GCP_STREAM_TIMEOUT
                  logger.info("GCP connections have a maximum lifetime. Re-establishing the batch stream to avoid " \
                              "timeout errors.")
                  @is_renewing_stream.set
                  y << ::Weaviate::V1::BatchStreamRequest.new(stop: ::Weaviate::V1::BatchStreamRequest::Stop.new)
                  throw :done
                end

                req = next_request(generation)
                if req == :empty
                  if @is_shutting_down.set?
                    logger.info("Server shutting down, closing the client-side of the stream")
                    throw :done
                  elsif @is_oom.set?
                    logger.info("Server out-of-memory, closing the client-side of the stream")
                    throw :done
                  elsif @is_hungup.set?
                    logger.info("Detected hung up stream, closing the client-side of the stream")
                    throw :done
                  end
                  logger.debug("Timed out getting request from queue, but not stopping, continuing...")
                  next
                end
                throw :done if req == :stale

                if req.nil?
                  logger.info("Batching finished, stopping and closing the client-side of the stream")
                  y << ::Weaviate::V1::BatchStreamRequest.new(stop: ::Weaviate::V1::BatchStreamRequest::Stop.new)
                  throw :done
                end
                @acks_lock.synchronize do
                  @inflight_objs.merge(req.uuids)
                  @inflight_refs.merge(req.beacons)
                end
                y << req.proto
              end
              logger.info("Batch send thread exiting due to exception...")
            end
          end
        end

        # Returns the next queued request (nil is the stop sentinel), :empty on timeout, or :stale if this
        # stream has been replaced in the meantime. Queue entries are wrapped in a 1-element Array so that
        # the nil sentinel can be told apart from a pop timeout.
        def next_request(generation)
          wrapped = @stale_lock.synchronize { @stale_reqs.shift }
          wrapped ||= @reqs.pop(timeout: 1)
          return :empty if wrapped.nil?
          return wrapped.first if generation == @stream_generation

          # this stream was replaced while we waited: hand the request to the next stream
          @stale_lock.synchronize { @stale_reqs.unshift(wrapped) }
          :stale
        end

        def recv
          @stream_generation += 1
          generation = @stream_generation
          @is_renewing_stream.clear
          @is_shutting_down.clear
          @is_hungup.clear
          @batch_grpc.stream(@connection, requests: send_enum(generation)) do |message|
            handle_message(message)
          end

          # restart the stream if we were shutdown by the node we were connected to ensuring that the index is
          # propagated properly from it to the new one
          if @is_shutting_down.set?
            reconnect
            logger.info("Restarting batch recv after shutdown...")
            return recv
          elsif @is_renewing_stream.set?
            # restart the stream if we are renewing it (GCP connections have a max lifetime)
            logger.info("Restarting batch recv after renewing stream...")
            return recv
          end

          logger.info("Server closed the stream from its side, shutting down batch")
          @shutdown_loop.set
        end

        def handle_message(message)
          logger.info("Batch stream started successfully") if message.has_started?

          if message.has_backoff? && message.backoff.batch_size != @batch_size && !@is_shutting_down.set? &&
             !@is_oom.set? && !@is_hungup.set? && !@is_renewing_stream.set? && !@is_stopped.set?
            @batch_size = message.backoff.batch_size
            logger.info("Updated batch size to #{@batch_size} as per server request")
          end

          if message.has_acks?
            @acks_lock.synchronize do
              @inflight_objs.subtract(message.acks.uuids.to_a)
              @inflight_refs.subtract(message.acks.beacons.to_a)
            end
          end

          handle_results(message.results) if message.has_results?

          if message.has_out_of_memory?
            logger.info("Server reported out-of-memory. Batching will wait at most 10 minutes for the server to " \
                        "scale-up. If the server does not recover within this time, the batch will terminate with " \
                        "an error.")
            @is_oom.set
            @oom_wait_time = message.out_of_memory.wait_time
            @objs_cache_lock.synchronize do
              @batch_objects.prepend(message.out_of_memory.uuids.filter_map { |uuid| @objs_cache[uuid] })
            end
            @refs_cache_lock.synchronize do
              @batch_references.prepend(message.out_of_memory.beacons.filter_map { |beacon| @refs_cache[beacon] })
            end
          end

          return unless message.has_shutting_down?

          logger.info("Received shutting down message from server")
          @is_shutting_down.set
          @is_oom.clear
        end

        def handle_results(results)
          result_objs = ::Weaviate::Outputs::Batch::BatchObjectReturn.new
          result_refs = ::Weaviate::Outputs::Batch::BatchReferenceReturn.new
          failed_objs = []
          failed_refs = []
          results.errors.each do |error|
            if error.has_uuid?
              cached = @objs_cache_lock.synchronize { @objs_cache.delete(error.uuid) }
              next if cached.nil?

              err = ::Weaviate::Outputs::Batch::ErrorObject.new(message: error.error, object_: cached)
              result_objs += ::Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [err],
                                                                               errors: { cached.index => err })
              failed_objs << err
              logger.warn({ "error" => error.error, "object" => error.uuid,
                            "action" => "use {client,collection}.batch.failed_objects to access this error" })
            end
            next unless error.has_beacon?

            cached = @refs_cache_lock.synchronize { @refs_cache.delete(error.beacon) }
            next if cached.nil?

            err = ::Weaviate::Outputs::Batch::ErrorReference.new(message: error.error, reference: cached)
            failed_refs << err
            result_refs += ::Weaviate::Outputs::Batch::BatchReferenceReturn.new(errors: { cached.index => err })
            logger.warn({ "error" => error.error, "reference" => error.beacon,
                          "action" => "use {client,collection}.batch.failed_references to access this error" })
          end
          results.successes.each do |success|
            if success.has_uuid?
              cached = @objs_cache_lock.synchronize { @objs_cache.delete(success.uuid) }
              next if cached.nil?

              @uuid_lookup_lock.synchronize { @uuid_lookup.delete(success.uuid) }
              uuid = ::Weaviate::Util.get_valid_uuid(success.uuid)
              result_objs += ::Weaviate::Outputs::Batch::BatchObjectReturn.new(_all_responses: [uuid],
                                                                               uuids: { cached.index => uuid })
            end
            @refs_cache_lock.synchronize { @refs_cache.delete(success.beacon) } if success.has_beacon?
          end
          @results_lock.synchronize do
            @results_for_wrapper.results.objs += result_objs
            @results_for_wrapper.results.refs += result_refs
            @results_for_wrapper.failed_objects.concat(failed_objs)
            @results_for_wrapper.failed_references.concat(failed_refs)
          end
        end

        def reconnect(retry_count = 0)
          if @consistency_level.to_s == "ALL" || @number_of_nodes == 1
            # check that all nodes are available before reconnecting
            up_nodes = @cluster.get_nodes_status
            while up_nodes.length != @number_of_nodes || up_nodes.any? { |node| node["status"] != "HEALTHY" }
              logger.info("Waiting for all nodes to be HEALTHY before reconnecting to batch stream...")
              sleep(5)
              up_nodes = @cluster.get_nodes_status
            end
          end
          begin
            logger.info("Trying to reconnect after shutdown... #{retry_count + 1}/5")
            @connection.close
            @connection.connect(force: true)
            logger.info("Reconnected successfully")
          rescue ::Weaviate::Exceptions::WeaviateStartUpError, ::Weaviate::Exceptions::WeaviateGRPCUnavailableError => e
            if retry_count < 5
              logger.warn("Failed to reconnect, after #{retry_count} attempts. Retrying...")
              sleep(2**retry_count)
              reconnect(retry_count + 1)
            else
              logger.error("Failed to reconnect after 5 attempts")
              @bg_exception = e
            end
          end
        end

        HANGUP_MESSAGES = ["Socket closed", "context canceled", "Connection reset",
                           "Received RST_STREAM with error code 2"].freeze

        def loop_wrapper
          batch_loop
          logger.info("exited batch requests loop thread")
        rescue StandardError => e
          logger.error(e)
          @bg_exception = e
        end

        def recv_wrapper
          loop do
            begin
              recv
              logger.info("exited batch receive thread")
            rescue StandardError => e
              if e.is_a?(::Weaviate::Exceptions::WeaviateBatchStreamError) &&
                 HANGUP_MESSAGES.any? { |m| e.message.include?(m) }
                logger.error("Socket hang up detected in batch receive thread: #{e.message}")
                @is_hungup.set
              else
                logger.error(e)
                logger.error(e.class)
                @bg_exception = e
              end
            end
            return unless @is_hungup.set?

            # this happens during ungraceful shutdown of the coordinator: restart the stream and add the
            # cached objects again
            logger.warn("Stream closed unexpectedly, restarting...")
            @stream_generation += 1 # retire the old request enumerator
            reconnect
            @objs_cache_lock.synchronize { @batch_objects.prepend(@objs_cache.values) }
            @refs_cache_lock.synchronize { @batch_references.prepend(@refs_cache.values) }
            # the cached objects were re-queued above, only keep a pending stop sentinel
            @stale_lock.synchronize { @stale_reqs.select! { |wrapped| wrapped.first.nil? } }
            @acks_lock.synchronize do
              @inflight_objs.clear
              @inflight_refs.clear
            end
            # start a new stream with a newly reconnected channel
          end
        end

        def start_bg_threads
          @bg_threads = BgThreads.new(
            loop: lambda {
              Thread.new do
                Thread.current.name = "BgBatchLoop"
                loop_wrapper
              end.tap { |t| t.report_on_exception = false }
            },
            recv: lambda {
              Thread.new do
                Thread.current.name = "BgBatchRecv"
                recv_wrapper
              end.tap { |t| t.report_on_exception = false }
            }
          )
          @bg_threads.start_recv
          @bg_threads.start_loop
        end

        def blocked?
          @inflight_objs.length >= @batch_size ||
            @inflight_refs.length >= @batch_size * 2 ||
            @is_renewing_stream.set? ||
            @is_shutting_down.set? ||
            @is_oom.set?
        end

        def check_bg_threads_alive
          return if all_threads_alive?

          raise @bg_exception || RuntimeError.new("Batch thread died unexpectedly")
        end
      end
    end
  end
end
