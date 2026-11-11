# frozen_string_literal: true

require_relative "base"
require_relative "sync"

module Weaviate
  module Collections
    module Batch
      # Port of weaviate.collections.batch.batch_wrapper._BatchWrapper: shared state of `client.batch` and
      # `collection.batch` (results of the last batch, wait_for_vector_indexing).
      class BatchWrapper
        def initialize(connection, consistency_level)
          @connection = connection
          @consistency_level = consistency_level
          @current_batch = nil
          # config options
          @batch_mode = DynamicBatching.new

          @batch_data = BatchDataWrapper.new
          @cluster = ClusterBatch.new(connection)
        end

        # Wait for all the vectors of the batch imported objects to be indexed.
        #
        # Upon network error, it will retry to get the shards' status for `how_many_failures` times with
        # exponential backoff (2**n seconds with n=0,1,2,...,how_many_failures).
        def wait_for_vector_indexing(shards: nil, how_many_failures: 5)
          if !shards.nil? && !shards.is_a?(Array)
            raise TypeError, "'shards' must be of type List[Shard]. Given type: #{shards.class}."
          end
          if !shards.nil? && !shards[0].is_a?(::Weaviate::Classes::Batch::Shard)
            raise TypeError, "'shards' must be of type List[Shard]. Given type: #{shards.class}."
          end

          waiting_count = 0
          until ready?(how_many_failures, shards)
            Batch.logger.debug("Waiting for async indexing to finish...") if (waiting_count % 20).zero?
            sleep(0.25)
            waiting_count += 1
          end
          Batch.logger.debug("Async indexing finished!")
        end

        def _get_shards_readiness(shard)
          path = "/schema/#{::Weaviate::Util.capitalize_first_letter(shard.collection)}/shards"
          params = shard.tenant.nil? ? nil : { "tenant" => shard.tenant }
          response = @connection.get(path, params: params)

          res = ::Weaviate::Util.decode_json_response_list(response, "Get shards' status")
          res.map do |s|
            if s.key?("per_node_status")
              s["per_node_status"].values.all? { |status| status == "READY" }
            else
              s["status"] == "READY"
            end
          end
        end

        # All failed objects from the last batch.
        def failed_objects = @batch_data.failed_objects

        # All failed references from the last batch.
        def failed_references = @batch_data.failed_references

        # The results of the last batch operation (a Weaviate::Outputs::Batch::BatchResult).
        def results = @batch_data.results

        private

        def ready?(max_count, shards, backoff_count = 0)
          targets = shards || @batch_data.imported_shards.to_a
          targets.map { |shard| _get_shards_readiness(shard) }.all?(&:all?)
        rescue StandardError => e
          Batch.logger.warn("Error while getting class shards statuses: #{e.message}, trying again with " \
                            "2**n=#{2**backoff_count}s exponential backoff with n=#{backoff_count}")
          raise e if backoff_count >= max_count

          sleep(2**backoff_count)
          ready?(max_count, shards, backoff_count + 1)
        end

        def vectorizer?(vectorizer)
          !vectorizer.nil? && vectorizer.to_s != "none"
        end

        def config_vector_config(config)
          config.respond_to?(:vector_config) ? config.vector_config : nil
        end

        def named_vectorizer?(vec_config)
          vectorizer = vec_config.vectorizer
          vectorizer = vectorizer.vectorizer if vectorizer.respond_to?(:vectorizer)
          vectorizer?(vectorizer)
        end
      end

      # Port of _ContextManagerSync. `start` = Python `__enter__`, `stop` = `__exit__`; `use { |batch| }` runs
      # a block between the two (what `with ... as batch:` does in Python).
      class ContextManagerSync
        def initialize(current_batch)
          @current_batch = current_batch
        end

        def start
          @current_batch._start
          @current_batch
        end
        alias __enter__ start

        def stop
          @current_batch._shutdown
          @current_batch._wait
          nil
        end
        alias __exit__ stop

        def use
          batch = start
          begin
            yield batch
          ensure
            stop
          end
        end
      end
    end
  end
end
