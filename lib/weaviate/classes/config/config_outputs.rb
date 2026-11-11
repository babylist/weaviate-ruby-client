# frozen_string_literal: true

require_relative "base"
require_relative "enums"
require_relative "fields"

# Output dataclasses (returned by `collection.config.get`) from weaviate/collections/classes/config.py.
# All are keyword-initialised; attribute names are the Python dataclass field names.
module Weaviate
  module Classes
    module Config
      # _BM25Config
      class BM25Config < ConfigBase
        attribute :b
        attribute :k1
      end

      # _StopwordsConfig
      class StopwordsConfig < ConfigBase
        attribute :preset
        attribute :additions
        attribute :removals
      end

      # _InvertedIndexConfig
      class InvertedIndexConfig < ConfigBase
        attribute :bm25
        attribute :cleanup_interval_seconds
        attribute :index_null_state
        attribute :index_property_length
        attribute :index_timestamps
        attribute :stopwords
        attribute :stopword_presets, default: nil
      end

      # _MultiTenancyConfig
      class MultiTenancyConfig < ConfigBase
        attribute :enabled
        attribute :auto_tenant_creation
        attribute :auto_tenant_activation
      end

      # _PropertyVectorizerConfig (plain dataclass)
      class PropertyVectorizerConfig < ::Weaviate::Model
        attribute :skip
        attribute :vectorize_property_name
      end

      # _TextAnalyzerConfig
      class TextAnalyzerConfig < ConfigBase
        attribute :ascii_fold
        attribute :ascii_fold_ignore
        attribute :stopword_preset
      end

      # _NestedProperty
      class NestedProperty < ConfigBase
        attribute :data_type
        attribute :description
        attribute :index_filterable
        attribute :index_searchable
        attribute :name
        attribute :nested_properties
        attribute :text_analyzer
        attribute :tokenization

        def to_dict
          out = super
          out["dataType"] = [data_type.to_s]
          out["nestedProperties"] = nested_properties.map(&:to_dict) if !nested_properties.nil? && !nested_properties.empty?
          out
        end
      end

      # _PropertyBase
      class PropertyBase < ConfigBase
        attribute :name
        attribute :description

        def to_dict
          out = { "name" => name }
          out["description"] = description unless description.nil?
          out
        end
      end

      # _Property (exported as PropertyConfig)
      class PropertyConfig < PropertyBase
        attribute :data_type
        attribute :index_filterable
        attribute :index_range_filters
        attribute :index_searchable
        attribute :nested_properties
        attribute :text_analyzer
        attribute :tokenization
        attribute :vectorizer_config
        attribute :vectorizer
        attribute :vectorizer_configs

        def to_dict
          out = super
          out["dataType"] = [data_type]
          out["indexFilterable"] = index_filterable
          out["indexSearchable"] = index_searchable
          out["indexRangeFilters"] = index_range_filters
          out["tokenization"] = tokenization.nil? || tokenization == "" ? nil : tokenization
          out["textAnalyzer"] = text_analyzer.to_dict unless text_analyzer.nil?
          out["nestedProperties"] = nested_properties.map(&:to_dict) if !nested_properties.nil? && !nested_properties.empty?
          module_config = {}
          module_config[vectorizer] = {} unless vectorizer.nil?
          unless vectorizer_config.nil?
            raise "vectorizer must be set when vectorizer_config is set" if vectorizer.nil?

            module_config[vectorizer] = {
              "skip" => vectorizer_config.skip,
              "vectorizePropertyName" => vectorizer_config.vectorize_property_name
            }
          end
          unless vectorizer_configs.nil?
            module_config = vectorizer_configs.to_h do |k, v|
              [k, { "skip" => v.skip, "vectorizePropertyName" => v.vectorize_property_name }]
            end
          end
          out["moduleConfig"] = module_config unless module_config.empty?
          out
        end
      end

      # _ReferenceProperty (exported as ReferencePropertyConfig)
      class ReferencePropertyConfig < PropertyBase
        attribute :target_collections

        def to_dict
          out = super
          out["dataType"] = target_collections
          out
        end
      end

      # _AsyncReplicationConfig
      class AsyncReplicationConfig < ConfigBase
        %i[
          max_workers hashtree_height frequency frequency_while_propagating alive_nodes_checking_frequency
          logging_frequency diff_batch_size diff_per_node_timeout pre_propagation_timeout propagation_timeout
          propagation_limit propagation_delay propagation_concurrency propagation_batch_size
        ].each { |f| attribute f }
      end

      # _ReplicationConfig
      class ReplicationConfig < ConfigBase
        attribute :factor
        attribute :async_enabled
        attribute :deletion_strategy
        attribute :async_config, default: nil
      end

      # _ShardingConfig
      class ShardingConfig < ConfigBase
        attribute :virtual_per_physical
        attribute :desired_count
        attribute :actual_count
        attribute :desired_virtual_count
        attribute :actual_virtual_count
        attribute :key
        attribute :strategy
        attribute :function
      end

      # _PQEncoderConfig
      class PQEncoderConfig < ConfigBase
        attribute :type_
        attribute :distribution

        def to_dict
          ret_dict = super
          ret_dict["type"] = ret_dict.delete("type").to_s
          ret_dict["distribution"] = ret_dict.delete("distribution").to_s
          ret_dict
        end
      end

      # _PQConfig
      class PQConfig < ConfigBase
        attribute :internal_bit_compression
        attribute :segments
        attribute :centroids
        attribute :training_limit
        attribute :encoder

        def bit_compression
          ::Weaviate::Warnings.bit_compression_in_pq_config
          internal_bit_compression
        end
      end

      # _BQConfig
      class BQConfig < ConfigBase
        attribute :cache
        attribute :rescore_limit
      end

      # _SQConfig
      class SQConfig < ConfigBase
        attribute :rescore_limit
        attribute :training_limit
      end

      # _RQConfig
      class RQConfig < ConfigBase
        attribute :cache
        attribute :bits
        attribute :rescore_limit
        attribute :centering
        attribute :training_limit
      end

      # _MuveraConfig
      class MuveraConfig < ConfigBase
        attribute :enabled
        attribute :ksim
        attribute :dprojections
        attribute :repetitions
      end

      # _MultiVectorConfig (exported as MultiVector)
      class MultiVectorConfig < ConfigBase
        attribute :encoding
        attribute :aggregation
      end
      MultiVector = MultiVectorConfig

      # _VectorIndexConfig
      class VectorIndexConfig < ConfigBase
        attribute :multi_vector
        attribute :quantizer

        def self.vector_index_type
          raise NotImplementedError
        end

        def vector_index_type = self.class.vector_index_type

        def to_dict
          out = super
          name = { PQConfig => "pq", BQConfig => "bq", SQConfig => "sq", RQConfig => "rq" }
                 .find { |klass, _| quantizer.is_a?(klass) }&.last
          out[name] = out.delete("quantizer").merge("enabled" => true) if name
          unless multi_vector.nil?
            mv = out.delete("multiVector")
            out["multivector"] = { "enabled" => true, "aggregation" => mv["aggregation"] }
            out["multivector"]["muvera"] = mv["encoding"] if mv.key?("encoding")
          end
          out
        end
      end

      # _VectorIndexConfigHNSW
      class VectorIndexConfigHNSW < VectorIndexConfig
        attribute :cleanup_interval_seconds
        attribute :distance_metric
        attribute :dynamic_ef_min
        attribute :dynamic_ef_max
        attribute :dynamic_ef_factor
        attribute :ef
        attribute :ef_construction
        attribute :filter_strategy
        attribute :flat_search_cutoff
        attribute :max_connections
        attribute :skip
        attribute :vector_cache_max_objects

        def self.vector_index_type = VectorIndexType::HNSW
      end

      # _VectorIndexConfigHFresh
      class VectorIndexConfigHFresh < VectorIndexConfig
        attribute :distance_metric
        attribute :max_posting_size_kb
        attribute :replicas
        attribute :search_probe

        def self.vector_index_type = VectorIndexType::HFRESH

        def to_dict
          out = super
          out["maxPostingSizeKB"] = out.delete("maxPostingSizeKb") if out.key?("maxPostingSizeKb")
          out
        end
      end

      # _VectorIndexConfigFlat
      class VectorIndexConfigFlat < VectorIndexConfig
        attribute :distance_metric
        attribute :vector_cache_max_objects

        def self.vector_index_type = VectorIndexType::FLAT
      end

      # _VectorIndexConfigDynamic
      class VectorIndexConfigDynamic < ConfigBase
        attribute :distance_metric
        attribute :hnsw
        attribute :flat
        attribute :threshold

        def self.vector_index_type = VectorIndexType::DYNAMIC
        def vector_index_type = self.class.vector_index_type
      end

      # _VectorIndexConfigNone: the index of this vector was dropped with
      # `collection.config.delete_vector_index()`; the vector can no longer be searched.
      class VectorIndexConfigNone < ConfigBase
        def self.vector_index_type = VectorIndexType::NONE
        def vector_index_type = self.class.vector_index_type
      end

      # _GenerativeConfig
      class GenerativeConfig < ConfigBase
        attribute :generative
        attribute :model
      end

      # _VectorizerConfig
      class VectorizerConfig < ConfigBase
        attribute :vectorizer
        attribute :model
        attribute :vectorize_collection_name
      end

      # _RerankerConfig
      class RerankerConfig < ConfigBase
        attribute :model
        attribute :reranker
      end

      # _NamedVectorizerConfig
      class NamedVectorizerConfig < ConfigBase
        attribute :vectorizer
        attribute :model
        attribute :source_properties

        def to_dict
          ret_dict = super
          ret_dict["properties"] = ret_dict.delete("sourceProperties") if ret_dict.key?("sourceProperties")
          ret_dict
        end
      end

      # _NamedVectorConfig
      class NamedVectorConfig < ConfigBase
        attribute :vectorizer
        attribute :vector_index_config

        def to_dict
          ret_dict = super
          ret_dict["vectorIndexType"] = vector_index_config.vector_index_type
          # match the server: a dropped index is reported without any `vectorIndexConfig`
          ret_dict.delete("vectorIndexConfig") if vector_index_config.is_a?(VectorIndexConfigNone)
          ret_dict
        end
      end

      # _ObjectTTLConfig. `time_to_live` is Integer seconds (Python: timedelta).
      class ObjectTTLConfig < ConfigBase
        attribute :enabled
        attribute :time_to_live
        attribute :filter_expired_objects
        attribute :delete_on

        def to_dict
          delete_on_value =
            case delete_on
            when "creationTime" then "_creationTimeUnix"
            when "updateTime" then "_lastUpdateTimeUnix"
            else delete_on
            end
          out = { "enabled" => enabled, "filterExpiredObjects" => filter_expired_objects, "deleteOn" => delete_on_value }
          out["defaultTtl"] = ConfigHelpers.seconds(time_to_live) unless time_to_live.nil?
          out
        end
      end

      # _CollectionConfig
      class CollectionConfig < ConfigBase
        attribute :name
        attribute :description
        attribute :generative_config
        attribute :inverted_index_config
        attribute :multi_tenancy_config
        attribute :object_ttl_config
        attribute :properties
        attribute :references
        attribute :replication_config
        attribute :reranker_config
        attribute :sharding_config
        attribute :vector_index_config
        attribute :vector_index_type
        attribute :vectorizer_config
        attribute :vectorizer
        attribute :vector_config

        def to_dict
          out = super
          out["class"] = out.delete("name")
          out["moduleConfig"] = {}
          [%w[generativeConfig generative], %w[vectorizerConfig vectorizer], %w[rerankerConfig reranker]].each do |key, mod|
            next unless out.key?(key)

            val = out.delete(key)
            module_name = val[mod]
            out["moduleConfig"][module_name] = val.fetch("model", {})
            vectorize_collection_name = val["vectorizeCollectionName"]
            unless vectorize_collection_name.nil?
              out["moduleConfig"][module_name]["vectorizeClassName"] = vectorize_collection_name
            end
          end

          if out.key?("vectorConfig")
            out["vectorConfig"].each do |k, v|
              extra_values = v["vectorizer"].delete("model") || {}
              vectorizer = v["vectorizer"].delete("vectorizer")
              out["vectorConfig"][k]["vectorizer"] = { vectorizer => extra_values.merge(v["vectorizer"]) }
            end
            # remove default values for single vector setup
            out.delete("vectorIndexType")
            out.delete("vectorIndexConfig")
          end

          out["properties"] = [*properties.map(&:to_dict), *references.map(&:to_dict)]
          out.delete("references")
          out
        end
      end

      # _CollectionConfigSimple
      class CollectionConfigSimple < ConfigBase
        attribute :name
        attribute :description
        attribute :generative_config
        attribute :properties
        attribute :references
        attribute :reranker_config
        attribute :vectorizer_config
        attribute :vectorizer
        attribute :vector_config
        attribute :object_ttl_config
      end

      # _ShardStatus (plain dataclass)
      class ShardStatus < ::Weaviate::Model
        attribute :name
        attribute :status
        attribute :vector_queue_size
        attribute :per_node_status
      end
    end
  end
end
