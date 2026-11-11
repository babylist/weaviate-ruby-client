# frozen_string_literal: true

require_relative "batch_wrapper"

module Weaviate
  module Collections
    module Batch
      # The user-facing methods of a client-level batch (Python BatchClientProtocol).
      module ClientBatchMethods
        # Add one object to this batch. If the UUID already exists the existing object is replaced.
        # Returns the UUID of the added object (auto-generated if none was given).
        # Raises WeaviateBatchValidationError if the provided options are invalid.
        def add_object(collection_ = nil, collection: nil, properties: nil, references: nil, uuid: nil, vector: nil,
                       tenant: nil)
          collection = Helpers.positional_or_keyword(collection_, collection, "collection")
          _add_object(collection: collection, properties: properties, references: references, uuid: uuid,
                      vector: vector, tenant: tenant_name(tenant))
        end

        # Add one reference to this batch. For multi-target references use a ReferenceToMulti as `to`.
        def add_reference(from_uuid_ = nil, from_collection:, from_property:, to:, from_uuid: nil, tenant: nil)
          from_uuid = Helpers.positional_or_keyword(from_uuid_, from_uuid, "from_uuid")
          _add_reference(from_object_uuid: from_uuid, from_object_collection: from_collection,
                         from_property_name: from_property, to: to, tenant: tenant_name(tenant))
        end

        private

        def tenant_name(tenant)
          tenant.is_a?(::Weaviate::Classes::Tenants::Tenant) ? tenant.name : tenant
        end
      end

      # Port of _BatchClient (client-side batching).
      class BatchClient < BatchBase
        include ClientBatchMethods
      end

      # Port of _BatchClientSync (server-side batching).
      class BatchClientSync < BatchBaseSync
        include ClientBatchMethods
      end

      # Port of _BatchClientWrapper: `client.batch`.
      #
      #   client.batch.dynamic { |batch| batch.add_object("Article", properties: { "title" => "x" }) }
      #   client.batch.failed_objects
      class BatchClientWrapper < BatchWrapper
        attr_reader :vectorizer_batching

        def initialize(connection, config:, consistency_level: nil)
          super(connection, consistency_level)
          @config = config
          @vectorizer_batching = nil
        end

        # Configure dynamic batching. With a block the batch is started, yielded and the final batch is sent
        # when the block returns; without a block the ContextManagerSync is returned (`start`/`stop`).
        def dynamic(consistency_level: nil, &block)
          @batch_mode = DynamicBatching.new
          @consistency_level = consistency_level
          run(create_batch_and_reset(BatchClient), &block)
        end

        # Configure fixed size batches. Note that the default is dynamic batching.
        def fixed_size(batch_size: 100, concurrent_requests: 2, consistency_level: nil, &block)
          @batch_mode = FixedSizeBatching.new(batch_size: batch_size, concurrent_requests: concurrent_requests)
          @consistency_level = consistency_level
          run(create_batch_and_reset(BatchClient), &block)
        end

        # Configure batches with a rate limited vectorizer (`requests_per_minute` objects per minute).
        def rate_limit(requests_per_minute:, consistency_level: nil, &block)
          @batch_mode = RateLimitedBatching.new(requests_per_minute: requests_per_minute)
          @consistency_level = consistency_level
          run(create_batch_and_reset(BatchClient), &block)
        end

        # @deprecated Use #stream instead.
        def experimental(concurrency: nil, consistency_level: nil, &block)
          stream(concurrency: concurrency, consistency_level: consistency_level, &block)
        end

        # Configure the batching context manager to use server-side batch streaming (Weaviate >= 1.36).
        def stream(concurrency: nil, consistency_level: nil, &block) # rubocop:disable Lint/UnusedMethodArgument
          version = @connection.weaviate_version
          if version.is_lower_than(1, 36, 0)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Server-side batching", version.to_s,
                                                                              "1.36.0")
          end

          # hard-code concurrency until client-side multi-threading is fixed
          @batch_mode = ServerSideBatching.new(concurrency: 1)
          @consistency_level = consistency_level
          run(create_batch_and_reset(BatchClientSync), &block)
        end

        private

        def run(context_manager, &block)
          return context_manager if block.nil?

          context_manager.use(&block)
        end

        def create_batch_and_reset(batch_client)
          detect_vectorizer_batching if @vectorizer_batching.nil? || !@vectorizer_batching
          @batch_data = BatchDataWrapper.new # clear old data
          ContextManagerSync.new(
            batch_client.new(connection: @connection, consistency_level: @consistency_level, results: @batch_data,
                             batch_mode: @batch_mode, vectorizer_batching: @vectorizer_batching)
          )
        end

        def detect_vectorizer_batching
          configs = @config.list_all(simple: true)
          vectorizer_batching = false
          configs.each_value do |config|
            vector_config = config_vector_config(config)
            if vector_config.nil?
              vectorizer_batching = configs.values.any? do |c|
                c.respond_to?(:vectorizer_config) && !c.vectorizer_config.nil?
              end
            else
              vectorizer_batching = vector_config.values.any? { |vec_config| named_vectorizer?(vec_config) }
            end
            break if vectorizer_batching
          end
          @vectorizer_batching = vectorizer_batching
        rescue ::Weaviate::Exceptions::UnexpectedStatusCodeError => e
          # we might not have the rights to query all collections
          raise e unless e.status_code == 403

          @vectorizer_batching = false
        end
      end
    end
  end
end
