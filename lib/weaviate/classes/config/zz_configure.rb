# frozen_string_literal: true

require_relative "models"

# Configure / Reconfigure factories from weaviate/collections/classes/config.py.
# This file sorts last so that the vectorizer / named-vector / vectors factories (defined in
# vectorizers.rb, named_vectors.rb and vectors.rb) are normally loaded already; if they are not,
# the nested constants are resolved lazily on first access.
module Weaviate
  module Classes
    module Config
      # Resolves nested factory constants that live in other files on first use.
      module LazyFactoryConstants
        def const_missing(name)
          target = self::LAZY_CONSTANTS[name]
          config = ::Weaviate::Classes::Config
          return super if target.nil? || !config.const_defined?(target, false)

          const_set(name, config.const_get(target, false))
        end

        def resolve_lazy_constants!
          config = ::Weaviate::Classes::Config
          self::LAZY_CONSTANTS.each do |name, target|
            const_set(name, config.const_get(target, false)) if !const_defined?(name, false) && config.const_defined?(target, false)
          end
        end
      end

      # Factory for the `collections.create()` configuration objects.
      module Configure
        extend LazyFactoryConstants

        LAZY_CONSTANTS = {
          Vectorizer: :Vectorizer,
          NamedVectors: :NamedVectors,
          Vectors: :Vectors,
          MultiVectors: :MultiVectors
        }.freeze

        Generative = ::Weaviate::Classes::Config::Generative
        Reranker = ::Weaviate::Classes::Config::Reranker
        VectorIndex = ::Weaviate::Classes::Config::VectorIndex
        ObjectTTL = ::Weaviate::Classes::Config::ObjectTTL
        Replication = ::Weaviate::Classes::Config::Replication

        module_function

        def text_analyzer(ascii_fold: nil, ascii_fold_ignore: nil, stopword_preset: nil)
          TextAnalyzerConfigCreate.new(
            ascii_fold: ascii_fold,
            ascii_fold_ignore: ascii_fold_ignore,
            stopword_preset: stopword_preset
          )
        end

        def inverted_index(bm25_b: nil, bm25_k1: nil, cleanup_interval_seconds: nil, index_timestamps: nil,
                           index_property_length: nil, index_null_state: nil, stopwords_preset: nil,
                           stopwords_additions: nil, stopwords_removals: nil, stopword_presets: nil)
          if (bm25_b.nil? && !bm25_k1.nil?) || (bm25_k1.nil? && !bm25_b.nil?)
            raise ArgumentError, "bm25_b and bm25_k1 must be specified together"
          end

          InvertedIndexConfigCreate.new(
            bm25: (BM25ConfigCreate.new(b: bm25_b, k1: bm25_k1) if !bm25_b.nil? && !bm25_k1.nil?),
            cleanupIntervalSeconds: cleanup_interval_seconds,
            indexTimestamps: index_timestamps,
            indexPropertyLength: index_property_length,
            indexNullState: index_null_state,
            stopwords: StopwordsCreate.new(
              preset: stopwords_preset,
              additions: stopwords_additions,
              removals: stopwords_removals
            ),
            stopwordPresets: stopword_presets
          )
        end

        def multi_tenancy(enabled: true, auto_tenant_creation: nil, auto_tenant_activation: nil)
          MultiTenancyConfigCreate.new(
            enabled: enabled,
            autoTenantCreation: auto_tenant_creation,
            autoTenantActivation: auto_tenant_activation
          )
        end

        def replication(factor: nil, async_enabled: nil, deletion_strategy: nil, async_config: nil)
          ::Weaviate::Warnings.async_enabled_field_removed_server_side unless async_enabled.nil?
          ReplicationConfigCreate.new(
            factor: factor,
            asyncEnabled: async_enabled,
            deletionStrategy: deletion_strategy,
            asyncConfig: async_config
          )
        end

        def sharding(virtual_per_physical: nil, desired_count: nil, actual_count: nil, desired_virtual_count: nil,
                     actual_virtual_count: nil)
          ::Weaviate::Warnings.sharding_actual_count_is_deprecated("actual_count") unless actual_count.nil?
          unless actual_virtual_count.nil?
            ::Weaviate::Warnings.sharding_actual_count_is_deprecated("actual_virtual_count")
          end
          ShardingConfigCreate.new(
            virtualPerPhysical: virtual_per_physical,
            desiredCount: desired_count,
            desiredVirtualCount: desired_virtual_count
          )
        end
      end

      # Factory for the `collection.config.update()` configuration objects (mutable settings only).
      module Reconfigure
        extend LazyFactoryConstants

        LAZY_CONSTANTS = {
          NamedVectors: :NamedVectorsUpdate,
          Vectors: :VectorsUpdate
        }.freeze

        VectorIndex = ::Weaviate::Classes::Config::VectorIndexUpdate
        Generative = ::Weaviate::Classes::Config::Generative # config is the same for create and update
        Reranker = ::Weaviate::Classes::Config::Reranker # config is the same for create and update
        ObjectTTL = ::Weaviate::Classes::Config::ObjectTTLUpdate
        Replication = ::Weaviate::Classes::Config::ReplicationUpdate

        module_function

        def inverted_index(bm25_b: nil, bm25_k1: nil, cleanup_interval_seconds: nil, stopwords_additions: nil,
                           stopwords_preset: nil, stopwords_removals: nil, stopword_presets: nil)
          InvertedIndexConfigUpdate.new(
            bm25: BM25ConfigUpdate.new(b: bm25_b, k1: bm25_k1),
            cleanupIntervalSeconds: cleanup_interval_seconds,
            stopwords: StopwordsUpdate.new(
              preset: stopwords_preset,
              additions: stopwords_additions,
              removals: stopwords_removals
            ),
            stopwordPresets: stopword_presets
          )
        end

        def replication(factor: nil, async_enabled: nil, deletion_strategy: nil, async_config: nil)
          ::Weaviate::Warnings.async_enabled_field_removed_server_side unless async_enabled.nil?
          ReplicationConfigUpdate.new(
            factor: factor,
            asyncEnabled: async_enabled,
            deletionStrategy: deletion_strategy,
            asyncConfig: async_config
          )
        end

        def multi_tenancy(auto_tenant_creation: nil, auto_tenant_activation: nil)
          MultiTenancyConfigUpdate.new(
            autoTenantCreation: auto_tenant_creation,
            autoTenantActivation: auto_tenant_activation
          )
        end
      end

      Configure.resolve_lazy_constants!
      Reconfigure.resolve_lazy_constants!
    end
  end
end
