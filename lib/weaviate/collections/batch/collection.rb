# frozen_string_literal: true

require_relative "batch_wrapper"

module Weaviate
  module Collections
    module Batch
      # The user-facing methods of a collection-level batch (Python BatchCollectionProtocol).
      module CollectionBatchMethods
        def init_collection(name, tenant)
          @name = name
          @tenant = tenant
        end

        # Add one object to this batch. If the UUID already exists the existing object is replaced.
        # `properties` may be given positionally or as a keyword. Returns the object's UUID.
        def add_object(properties_ = nil, properties: nil, references: nil, uuid: nil, vector: nil)
          properties = Helpers.positional_or_keyword(properties_, properties, "properties", required: false)
          _add_object(collection: @name, properties: properties, references: references, uuid: uuid, vector: vector,
                      tenant: @tenant)
        end

        # Add a reference to this batch. For multi-target references use a ReferenceToMulti as `to`.
        def add_reference(from_uuid_ = nil, from_property:, to:, from_uuid: nil)
          from_uuid = Helpers.positional_or_keyword(from_uuid_, from_uuid, "from_uuid")
          _add_reference(from_object_uuid: from_uuid, from_object_collection: @name,
                         from_property_name: from_property, to: to, tenant: @tenant)
        end
      end

      # Port of _BatchCollection (client-side batching).
      class BatchCollection < BatchBase
        include CollectionBatchMethods

        def initialize(connection:, consistency_level:, results:, batch_mode:, name:, tenant:, vectorizer_batching:,
                       executor: nil)
          super(connection: connection, consistency_level: consistency_level, results: results,
                batch_mode: batch_mode, executor: executor, vectorizer_batching: vectorizer_batching)
          init_collection(name, tenant)
        end
      end

      # Port of _BatchCollectionSync (server-side batching).
      class BatchCollectionSync < BatchBaseSync
        include CollectionBatchMethods

        def initialize(connection:, consistency_level:, results:, name:, tenant:, executor: nil, batch_mode: nil,
                       vectorizer_batching: false)
          super(connection: connection, consistency_level: consistency_level, results: results,
                batch_mode: batch_mode, executor: executor, vectorizer_batching: vectorizer_batching)
          init_collection(name, tenant)
        end
      end

      # Port of _BatchCollectionWrapper: `collection.batch`.
      #
      #   collection.batch.dynamic { |batch| batch.add_object(properties: { "title" => "x" }) }
      #   collection.batch.failed_objects
      class BatchCollectionWrapper < BatchWrapper
        attr_reader :vectorizer_batching

        def initialize(connection:, consistency_level:, name:, tenant:, config:, batch_client: BatchCollection)
          super(connection, consistency_level)
          @name = name
          @tenant = tenant
          @config = config
          @vectorizer_batching = nil
          @batch_client = batch_client
        end

        # Configure dynamic batching. With a block the batch is started, yielded and the final batch is sent
        # when the block returns; without a block the ContextManagerSync is returned (`start`/`stop`).
        def dynamic(&block)
          @batch_mode = DynamicBatching.new
          run(create_batch_and_reset(BatchCollection), &block)
        end

        # Configure fixed size batches. Note that the default is dynamic batching.
        def fixed_size(batch_size: 100, concurrent_requests: 2, &block)
          @batch_mode = FixedSizeBatching.new(batch_size: batch_size, concurrent_requests: concurrent_requests)
          run(create_batch_and_reset(BatchCollection), &block)
        end

        # Configure batches with a rate limited vectorizer (`requests_per_minute` objects per minute).
        def rate_limit(requests_per_minute:, &block)
          @batch_mode = RateLimitedBatching.new(requests_per_minute: requests_per_minute)
          run(create_batch_and_reset(BatchCollection), &block)
        end

        # @deprecated Use #stream instead.
        def experimental(concurrency: nil, &block)
          stream(concurrency: concurrency, &block)
        end

        # Configure the batching context manager to use server-side batch streaming (Weaviate >= 1.36).
        def stream(concurrency: nil, &block)
          version = @connection.weaviate_version
          if version.is_lower_than(1, 36, 0)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new("Server-side batching", version.to_s,
                                                                              "1.36.0")
          end

          @batch_mode = ServerSideBatching.new(concurrency: concurrency || 1)
          run(create_batch_and_reset(BatchCollectionSync), &block)
        end

        private

        def run(context_manager, &block)
          return context_manager if block.nil?

          context_manager.use(&block)
        end

        def create_batch_and_reset(batch_client)
          detect_vectorizer_batching if @vectorizer_batching.nil?
          @batch_data = BatchDataWrapper.new # clear old data
          ContextManagerSync.new(
            batch_client.new(connection: @connection, consistency_level: @consistency_level, results: @batch_data,
                             batch_mode: @batch_mode, name: @name, tenant: @tenant,
                             vectorizer_batching: @vectorizer_batching)
          )
        end

        def detect_vectorizer_batching
          config = @config.get(simple: true)
          vector_config = config_vector_config(config)
          @vectorizer_batching =
            if vector_config.nil?
              vectorizer?(config.respond_to?(:vectorizer) ? config.vectorizer : nil)
            else
              vector_config.values.any? { |vec_config| named_vectorizer?(vec_config) }
            end
        rescue ::Weaviate::Exceptions::UnexpectedStatusCodeError => e
          # collection does not have to exist if autoschema is enabled. Individual objects will be validated
          # and might fail
          raise e unless e.status_code == 404

          @vectorizer_batching = false
        end
      end
    end
  end
end
