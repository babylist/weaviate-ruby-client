# frozen_string_literal: true

require_relative "base"
require_relative "enums"
require_relative "fields"
require_relative "generative"
require_relative "object_ttl"
require_relative "vector_index"

# Create/update models from weaviate/collections/classes/config.py
module Weaviate
  module Classes
    module Config
      ASYNC_REPLICATION_FIELDS = %i[
        maxWorkers hashtreeHeight frequency frequencyWhilePropagating aliveNodesCheckingFrequency loggingFrequency
        diffBatchSize diffPerNodeTimeout prePropagationTimeout propagationTimeout propagationLimit propagationDelay
        propagationConcurrency propagationBatchSize
      ].freeze

      # ShardingConfigCreate
      class ShardingConfigCreate < ConfigCreateModel
        include Fields

        field :virtualPerPhysical, :int
        field :desiredCount, :int
        field :desiredVirtualCount, :int
        field :key, :str, default: "_id"
        field :strategy, :str, default: "hash"
        field :function, :str, default: "murmur3"
      end

      # _AsyncReplicationConfigCreate
      class AsyncReplicationConfigCreate < ConfigCreateModel
        include Fields

        ASYNC_REPLICATION_FIELDS.each { |f| field f, :int }
      end

      # _AsyncReplicationConfigUpdate
      class AsyncReplicationConfigUpdate < ConfigUpdateModel
        include Fields

        ASYNC_REPLICATION_FIELDS.each { |f| field f, :int }
      end

      # ReplicationConfigCreate
      class ReplicationConfigCreate < ConfigCreateModel
        include Fields

        field :factor, :int
        field :asyncEnabled, :bool
        field :asyncConfig, AsyncReplicationConfigCreate
        field :deletionStrategy, ReplicationDeletionStrategy
      end

      # ReplicationConfigUpdate
      class ReplicationConfigUpdate < ConfigUpdateModel
        include Fields

        field :factor, :int
        field :asyncEnabled, :bool
        field :asyncConfig, AsyncReplicationConfigUpdate
        field :deletionStrategy, ReplicationDeletionStrategy

        def merge_with_existing(schema)
          schema["factor"] = factor unless factor.nil?
          schema["asyncEnabled"] = asyncEnabled unless asyncEnabled.nil?
          schema["deletionStrategy"] = deletionStrategy.to_s unless deletionStrategy.nil?
          # Replace the entire asyncConfig (like generative/reranker) rather than merging, so omitted
          # fields revert to server defaults.
          schema["asyncConfig"] = asyncConfig.model_dump(exclude_none: true) unless asyncConfig.nil?
          schema
        end
      end

      # _BM25ConfigCreate
      class BM25ConfigCreate < ConfigCreateModel
        include Fields

        field :b, :float, required: true
        field :k1, :float, required: true
      end

      # _BM25ConfigUpdate
      class BM25ConfigUpdate < ConfigUpdateModel
        include Fields

        field :b, :float
        field :k1, :float
      end

      # _StopwordsCreate
      class StopwordsCreate < ConfigCreateModel
        include Fields

        field :preset, StopwordsPreset
        field :additions, [:list, :str]
        field :removals, [:list, :str]
      end

      # _StopwordsUpdate
      class StopwordsUpdate < ConfigUpdateModel
        include Fields

        field :preset, StopwordsPreset
        field :additions, [:list, :str]
        field :removals, [:list, :str]
      end

      # InvertedIndexConfigCreate
      class InvertedIndexConfigCreate < ConfigCreateModel
        include Fields

        field :bm25, BM25ConfigCreate
        field :cleanupIntervalSeconds, :int
        field :indexTimestamps, :bool
        field :indexPropertyLength, :bool
        field :indexNullState, :bool
        field :stopwords, StopwordsCreate, required: true
        field :stopwordPresets, [:hash_of, [:list, :str]]
      end

      # InvertedIndexConfigUpdate
      class InvertedIndexConfigUpdate < ConfigUpdateModel
        include Fields

        field :bm25, BM25ConfigUpdate
        field :cleanupIntervalSeconds, :int
        field :stopwords, StopwordsUpdate
        field :stopwordPresets, [:hash_of, [:list, :str]]
      end

      # MultiTenancyConfigCreate
      class MultiTenancyConfigCreate < ConfigCreateModel
        include Fields

        field :enabled, :bool, required: true
        field :autoTenantCreation, :bool
        field :autoTenantActivation, :bool
      end

      # MultiTenancyConfigUpdate
      class MultiTenancyConfigUpdate < ConfigUpdateModel
        include Fields

        field :autoTenantCreation, :bool
        field :autoTenantActivation, :bool
      end

      # _TextAnalyzerConfigCreate: per-property text analysis options (ASCII folding, stopword preset).
      class TextAnalyzerConfigCreate < ConfigCreateModel
        include Fields

        field :asciiFold, :bool, as: :ascii_fold
        field :asciiFoldIgnore, [:list, :str], as: :ascii_fold_ignore
        field :stopwordPreset, :str, as: :stopword_preset

        def after_initialize
          super
          return unless asciiFold != true && !asciiFoldIgnore.nil?

          raise ValidationError, "asciiFoldIgnore cannot be set when asciiFold is not enabled"
        end
      end

      # Property: a data property of a collection.
      class Property < ConfigCreateModel
        include Fields

        field :name, :str, required: true
        field :dataType, DataType, required: true, as: :data_type
        field :description, :str
        field :indexFilterable, :bool, as: :index_filterable
        field :indexSearchable, :bool, as: :index_searchable
        field :indexRangeFilters, :bool, as: :index_range_filters
        field :nestedProperties, [:union, Property, [:list, Property]], as: :nested_properties
        field :skip_vectorization, :bool, default: false
        field :textAnalyzer, TextAnalyzerConfigCreate, as: :text_analyzer
        field :tokenization, Tokenization
        field :vectorize_property_name, :bool, default: true

        def after_initialize
          super
          raise ValidationError, "Property name '#{name}' is reserved and cannot be used" if name == "vector"
        end

        def to_dict(vectorizers = nil)
          ret_dict = super()
          ret_dict["dataType"] = [ret_dict["dataType"]]
          unless vectorizers.nil?
            vectorizers.each do |vectorizer|
              next if vectorizer.nil?

              value = ConfigHelpers.enum_value(vectorizer)
              next if value == "none"

              ret_dict["moduleConfig"] ||= {}
              ret_dict["moduleConfig"][value] = {
                "skip" => skip_vectorization,
                "vectorizePropertyName" => vectorize_property_name
              }
            end
            ret_dict.delete("skip_vectorization")
            ret_dict.delete("vectorize_property_name")
          end
          unless nestedProperties.nil?
            ret_dict["nestedProperties"] =
              nestedProperties.is_a?(Array) ? nestedProperties.map(&:to_dict) : [nestedProperties.to_dict]
          end
          ret_dict["textAnalyzer"] = textAnalyzer.to_dict unless textAnalyzer.nil?
          ret_dict
        end
      end

      # ReferencePropertyBase
      class ReferencePropertyBase < ConfigCreateModel
        include Fields

        field :name, :str, required: true

        def after_initialize
          super
          raise ValidationError, "Property name '#{name}' is reserved and cannot be used" if %w[id vector].include?(name)
        end
      end

      # ReferencePropertyMultiTarget: a cross reference to multiple target collections.
      class ReferencePropertyMultiTarget < ReferencePropertyBase
        field :target_collections, [:list, :str], required: true
        field :description, :str

        def to_dict
          ret_dict = super
          ret_dict["dataType"] = target_collections.map { |t| ::Weaviate::Util.capitalize_first_letter(t) }
          ret_dict.delete("target_collections")
          ret_dict
        end
      end

      # ReferenceProperty: a cross reference to a single target collection.
      class ReferenceProperty < ReferencePropertyBase
        MultiTarget = ReferencePropertyMultiTarget

        field :target_collection, :str, required: true
        field :description, :str

        def to_dict
          ret_dict = super
          ret_dict["dataType"] = [::Weaviate::Util.capitalize_first_letter(target_collection)]
          ret_dict.delete("target_collection")
          ret_dict
        end
      end

      # Shared helpers for the collection create/update models.
      module CollectionConfigHelpers
        module_function

        def add_to_module_config(return_dict, addition_key, addition_val)
          if return_dict.key?("moduleConfig")
            return_dict["moduleConfig"][addition_key] = addition_val
          else
            return_dict["moduleConfig"] = { addition_key => addition_val }
          end
        end

        def config_class(name)
          ::Weaviate::Classes::Config.const_get(name, false)
        end

        # isinstance check against a class that may live in another (lazily loaded) file.
        def instance_of_config?(value, name)
          ::Weaviate::Classes::Config.const_defined?(name, false) && value.is_a?(config_class(name))
        end

        # Python `str(val)` for scalar fields.
        def python_str(val)
          case val
          when true then "True"
          when false then "False"
          else val.to_s
          end
        end
      end

      # _CollectionConfigCreate: its #to_dict is the body sent by `client.collections.create`.
      class CollectionConfigCreate < ConfigCreateModel
        include Fields

        field :name, :str, required: true
        field :properties, [:list, Property]
        field :references, [:list, ReferencePropertyBase]
        field :description, :str
        field :invertedIndexConfig, InvertedIndexConfigCreate, as: :inverted_index_config
        field :multiTenancyConfig, MultiTenancyConfigCreate, as: :multi_tenancy_config
        field :objectTtlConfig, ObjectTTLConfigCreate, as: :object_ttl_config
        field :replicationConfig, ReplicationConfigCreate, as: :replication_config
        field :shardingConfig, ShardingConfigCreate, as: :sharding_config
        field :vectorIndexConfig, VectorIndexConfigCreate, as: :vector_index_config
        field :vectorizerConfig, nil, as: :vectorizer_config
        field :vectorConfig, nil, as: :vector_config
        field :generativeSearch, GenerativeProvider, as: :generative_config
        field :rerankerConfig, RerankerProvider, as: :reranker_config

        def after_initialize
          super
          check_top_level_property_names!
          validate_vector_names!(vectorizerConfig)
          validate_vector_names!(vectorConfig)
          inject_vector_config_none!
          self.name = ::Weaviate::Util.capitalize_first_letter(name)
        end

        def to_dict(emit_default_vector_index_type: true)
          h = CollectionConfigHelpers
          ret_dict = {}

          self.class.attribute_names.each do |cls_field|
            val = public_send(cls_field)
            next if %i[name model properties references].include?(cls_field) || val.nil?

            key = cls_field.to_s
            if [true, false].include?(val) || val.is_a?(Numeric) || val.is_a?(String)
              ret_dict[key] = h.python_str(val)
            elsif val.is_a?(GenerativeProvider)
              h.add_to_module_config(ret_dict, ConfigHelpers.enum_value(val.generative), val.to_dict)
            elsif val.is_a?(RerankerProvider)
              h.add_to_module_config(ret_dict, ConfigHelpers.enum_value(val.reranker), val.to_dict)
            elsif h.instance_of_config?(val, :VectorizerConfigCreate)
              vectorizer = ConfigHelpers.enum_value(val.vectorizer)
              ret_dict["vectorizer"] = vectorizer
              h.add_to_module_config(ret_dict, vectorizer, val.to_dict) unless vectorizer == "none"
            elsif val.is_a?(VectorIndexConfigCreate)
              ret_dict["vectorIndexType"] = val.vector_index_type
              ret_dict[key] = val.to_dict
            elsif h.instance_of_config?(val, :VectorConfigCreate)
              ret_dict["vectorConfig"] = {
                (val.name || "default") => val.to_dict(emit_default_vector_index_type: emit_default_vector_index_type)
              }
            elsif val.is_a?(Array) && !val.empty? && val.all? { |i| h.instance_of_config?(i, :NamedVectorConfigCreate) }
              ret_dict["vectorConfig"] = val.to_h do |item|
                [item.name, item.to_dict(emit_default_vector_index_type: emit_default_vector_index_type)]
              end
            elsif val.is_a?(Array) && !val.empty? && val.all? { |i| h.instance_of_config?(i, :VectorConfigCreate) }
              ret_dict["vectorConfig"] = {}
              val.each do |item|
                if item.name.nil?
                  raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                        "Vector config name must be set when specifying multiple vectors"
                end

                ret_dict["vectorConfig"][item.name] =
                  item.to_dict(emit_default_vector_index_type: emit_default_vector_index_type)
              end
            else
              raise TypeError, "unexpected value for #{key}: #{val.inspect}" unless val.is_a?(ConfigCreateModel)

              ret_dict[key] = val.to_dict
            end
          end
          if vectorIndexConfig.nil? && !ret_dict.key?("vectorConfig") && emit_default_vector_index_type
            ret_dict["vectorIndexType"] = VectorIndexType::HNSW
          end

          ret_dict["class"] = name
          add_props(properties, ret_dict)
          add_props(references, ret_dict)
          ret_dict
        end

        private

        def check_top_level_property_names!
          return if properties.nil?

          properties.each do |prop|
            raise ::Weaviate::Exceptions::WeaviateInsertInvalidPropertyError, { "name" => prop.name } if prop.name == "id"
          end
        end

        def validate_vector_names!(value)
          return unless value.is_a?(Array)

          names = value.map(&:name)
          return if names.uniq.length == names.length

          dups = names.select { |n| names.count(n) > 1 }.uniq
          raise ValidationError, "Vector config names must be unique. Found duplicates: #{dups}"
        end

        def inject_vector_config_none!
          return unless vectorConfig.nil? && vectorizerConfig.nil? && vectorIndexConfig.nil?

          cfg = ::Weaviate::Classes::Config
          self.vectorConfig = cfg::VectorConfigCreate.new(
            name: "default",
            vectorizer: cfg::VectorizerConfigCreate.new(vectorizer: cfg::Vectorizers::NONE)
          )
        end

        def property_vectorizers
          h = CollectionConfigHelpers
          if h.instance_of_config?(vectorizerConfig, :VectorizerConfigCreate)
            [vectorizerConfig.vectorizer]
          elsif vectorizerConfig.nil?
            nil
          else
            vectorizerConfig.map { |conf| conf.vectorizer.vectorizer }
          end
        end

        def add_props(props, ret_dict)
          return if props.nil?

          warn_vectorization_flags_ignored(props)
          existing_props = ret_dict.fetch("properties", [])
          props.each do |prop|
            existing_props << (prop.is_a?(Property) ? prop.to_dict(property_vectorizers) : prop.to_dict)
          end
          ret_dict["properties"] = existing_props
        end

        def warn_vectorization_flags_ignored(props)
          return if vectorConfig.nil?

          vector_configs = vectorConfig.is_a?(Array) ? vectorConfig : [vectorConfig]
          return if vector_configs.all? { |conf| ConfigHelpers.enum_value(conf.vectorizer.vectorizer) == "none" }

          props.each do |prop|
            next unless prop.is_a?(Property) && prop.model_fields_set.include?(:skip_vectorization)

            ::Weaviate::Warnings.skip_vectorization_ignored_with_vector_config(prop.name)
          end
        end
      end

      # _CollectionConfigUpdate: merged into the existing schema by `collection.config.update`.
      class CollectionConfigUpdate < ConfigUpdateModel
        include Fields

        QUANTIZER_CONFLICTS = {
          "pq" => %w[bq sq rq],
          "bq" => %w[pq sq rq],
          "sq" => %w[pq bq rq],
          "rq" => %w[pq bq sq]
        }.freeze

        field :description, :str
        field :property_descriptions, [:hash_of, :str]
        field :invertedIndexConfig, InvertedIndexConfigUpdate, as: :inverted_index_config
        field :objectTtlConfig, ObjectTTLConfigUpdate, as: :object_ttl_config
        field :replicationConfig, ReplicationConfigUpdate, as: :replication_config
        field :vectorIndexConfig, VectorIndexConfigUpdate, as: :vector_index_config
        field :vectorizerConfig, nil, as: :vectorizer_config
        field :vectorConfig, nil, as: :vector_config
        field :multiTenancyConfig, MultiTenancyConfigUpdate, as: :multi_tenancy_config
        field :generativeConfig, GenerativeProvider, as: :generative_config
        field :rerankerConfig, RerankerProvider, as: :reranker_config

        def after_initialize
          super
          return if vectorConfig.nil?

          unless vectorizerConfig.nil?
            raise ValidationError,
                  "Cannot specify vectorizerConfig when also specifying vectorConfig. Please use one or the other."
          end
          return if vectorIndexConfig.nil?

          raise ValidationError,
                "Cannot specify vectorIndexConfig when also specifying vectorConfig. Please use one or the other."
        end

        def merge_with_existing(schema)
          schema["description"] = description unless description.nil?
          merge_property_descriptions(schema) unless property_descriptions.nil?
          unless invertedIndexConfig.nil?
            schema["invertedIndexConfig"] = invertedIndexConfig.merge_with_existing(schema["invertedIndexConfig"])
          end
          unless replicationConfig.nil?
            schema["replicationConfig"] = replicationConfig.merge_with_existing(schema["replicationConfig"])
          end
          unless multiTenancyConfig.nil?
            schema["multiTenancyConfig"] = multiTenancyConfig.merge_with_existing(schema["multiTenancyConfig"])
          end
          unless objectTtlConfig.nil?
            schema["objectTtlConfig"] = objectTtlConfig.merge_with_existing(schema.fetch("objectTtlConfig", {}))
          end
          unless vectorIndexConfig.nil?
            check_quantizers(vectorIndexConfig.quantizer, schema["vectorIndexConfig"])
            schema["vectorIndexConfig"] = vectorIndexConfig.merge_with_existing(schema["vectorIndexConfig"])
          end
          unless generativeConfig.nil?
            # clear any existing generative config
            if schema.key?("moduleConfig")
              schema["moduleConfig"] = schema["moduleConfig"].reject { |k, _| k.include?("generative") }
            end
            CollectionConfigHelpers.add_to_module_config(
              schema, ConfigHelpers.enum_value(generativeConfig.generative), generativeConfig.to_dict
            )
          end
          unless rerankerConfig.nil?
            # clear any existing reranker config
            if schema.key?("moduleConfig")
              schema["moduleConfig"] = schema["moduleConfig"].reject { |k, _| k.include?("reranker") }
            end
            CollectionConfigHelpers.add_to_module_config(
              schema, ConfigHelpers.enum_value(rerankerConfig.reranker), rerankerConfig.to_dict
            )
          end
          unless vectorizerConfig.nil?
            if vectorizerConfig.is_a?(VectorIndexConfigUpdate)
              check_quantizers(vectorizerConfig.quantizer, schema["vectorIndexConfig"])
              schema["vectorIndexConfig"] = vectorizerConfig.merge_with_existing(schema["vectorIndexConfig"])
            else
              vectorizerConfig.each { |vc| merge_named_vector(schema, vc) }
            end
          end
          unless vectorConfig.nil?
            vcs = vectorConfig.is_a?(Array) ? vectorConfig : [vectorConfig]
            vcs.each { |vc| merge_named_vector(schema, vc) }
          end
          schema
        end

        private

        def merge_property_descriptions(schema)
          p = schema["properties"]
          if p.nil?
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Cannot update property descriptions without existing properties in the schema"
          end

          props = p.to_h { |prop| [prop["name"], prop] }
          property_descriptions.each do |prop_name, prop_desc|
            prop_name = prop_name.to_s
            unless props.key?(prop_name)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "Property #{prop_name} does not exist in the existing properties"
            end

            props[prop_name]["description"] = prop_desc
          end
        end

        def merge_named_vector(schema, vector_config)
          existing = existing_vector_index_config(schema, vector_config.name)
          vic = vector_config.vectorIndexConfig
          check_quantizers(vic.quantizer, existing)
          schema["vectorConfig"][vector_config.name]["vectorIndexConfig"] = vic.merge_with_existing(existing)
          schema["vectorConfig"][vector_config.name]["vectorIndexType"] = vic.vector_index_type
        end

        def existing_vector_index_config(schema, name)
          # `vectorConfig` is omitted entirely once every named vector has been dropped.
          if !schema.key?("vectorConfig") || !schema["vectorConfig"].key?(name)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Vector config with name #{name} does not exist in the existing vector config"
          end
          existing = schema["vectorConfig"][name]
          unless existing.key?("vectorIndexConfig")
            # the index was dropped with `collection.config.delete_vector_index()`, Weaviate reports such a
            # vector as `vectorIndexType: "none"` without any index config to merge into
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Vector config with name #{name} has no vector index, it was dropped with " \
                  "collection.config.delete_vector_index() and cannot be updated. Once the drop " \
                  "completes, a new vector with this name can be added with " \
                  "collection.config.add_vector()"
          end
          existing["vectorIndexConfig"]
        end

        def check_quantizers(quantizer, vector_index_config)
          return if quantizer.nil?

          conflicts = QUANTIZER_CONFLICTS[quantizer.class.quantizer_name]
          return if conflicts.nil?

          enabled = conflicts.any? { |q| vector_index_config.fetch(q, { "enabled" => false })["enabled"] }
          return unless enabled

          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "Cannot update vector index config #{vector_index_config} to change its quantizer. To do this, " \
                "you must recreate the collection."
        end
      end

      # _Replication (Configure.Replication)
      module Replication
        def self.async_config(max_workers: nil, hashtree_height: nil, frequency: nil, frequency_while_propagating: nil,
                              alive_nodes_checking_frequency: nil, logging_frequency: nil, diff_batch_size: nil,
                              diff_per_node_timeout: nil, pre_propagation_timeout: nil, propagation_timeout: nil,
                              propagation_limit: nil, propagation_delay: nil, propagation_concurrency: nil,
                              propagation_batch_size: nil)
          ::Weaviate::Warnings.async_replication_field_removed_server_side("max_workers") unless max_workers.nil?
          unless alive_nodes_checking_frequency.nil?
            ::Weaviate::Warnings.async_replication_field_removed_server_side("alive_nodes_checking_frequency")
          end
          AsyncReplicationConfigCreate.new(
            maxWorkers: max_workers, hashtreeHeight: hashtree_height, frequency: frequency,
            frequencyWhilePropagating: frequency_while_propagating,
            aliveNodesCheckingFrequency: alive_nodes_checking_frequency, loggingFrequency: logging_frequency,
            diffBatchSize: diff_batch_size, diffPerNodeTimeout: diff_per_node_timeout,
            prePropagationTimeout: pre_propagation_timeout, propagationTimeout: propagation_timeout,
            propagationLimit: propagation_limit, propagationDelay: propagation_delay,
            propagationConcurrency: propagation_concurrency, propagationBatchSize: propagation_batch_size
          )
        end
      end

      # _ReplicationUpdate (Reconfigure.Replication)
      module ReplicationUpdate
        def self.async_config(max_workers: nil, hashtree_height: nil, frequency: nil, frequency_while_propagating: nil,
                              alive_nodes_checking_frequency: nil, logging_frequency: nil, diff_batch_size: nil,
                              diff_per_node_timeout: nil, pre_propagation_timeout: nil, propagation_timeout: nil,
                              propagation_limit: nil, propagation_delay: nil, propagation_concurrency: nil,
                              propagation_batch_size: nil)
          ::Weaviate::Warnings.async_replication_field_removed_server_side("max_workers") unless max_workers.nil?
          unless alive_nodes_checking_frequency.nil?
            ::Weaviate::Warnings.async_replication_field_removed_server_side("alive_nodes_checking_frequency")
          end
          AsyncReplicationConfigUpdate.new(
            maxWorkers: max_workers, hashtreeHeight: hashtree_height, frequency: frequency,
            frequencyWhilePropagating: frequency_while_propagating,
            aliveNodesCheckingFrequency: alive_nodes_checking_frequency, loggingFrequency: logging_frequency,
            diffBatchSize: diff_batch_size, diffPerNodeTimeout: diff_per_node_timeout,
            prePropagationTimeout: pre_propagation_timeout, propagationTimeout: propagation_timeout,
            propagationLimit: propagation_limit, propagationDelay: propagation_delay,
            propagationConcurrency: propagation_concurrency, propagationBatchSize: propagation_batch_size
          )
        end
      end

      # _VectorIndexQuantizerUpdate (Reconfigure.VectorIndex.Quantizer)
      module VectorIndexQuantizerUpdate
        def self.pq(bit_compression: nil, centroids: nil, encoder_distribution: nil, encoder_type: nil, segments: nil,
                    training_limit: nil, enabled: true)
          ::Weaviate::Warnings.bit_compression_in_pq_config unless bit_compression.nil?
          PQConfigUpdate.new(
            enabled: enabled,
            centroids: centroids,
            segments: segments,
            trainingLimit: training_limit,
            encoder: (if !encoder_type.nil? || !encoder_distribution.nil?
                        PQEncoderConfigUpdate.new(type_: encoder_type, distribution: encoder_distribution)
                      end)
          )
        end

        def self.bq(rescore_limit: nil, enabled: true)
          BQConfigUpdate.new(rescoreLimit: rescore_limit, enabled: enabled)
        end

        def self.sq(rescore_limit: nil, training_limit: nil, enabled: true)
          SQConfigUpdate.new(enabled: enabled, rescoreLimit: rescore_limit, trainingLimit: training_limit)
        end

        def self.rq(rescore_limit: nil, enabled: true, bits: nil, centering: nil, training_limit: nil)
          RQConfigUpdate.new(enabled: enabled, rescoreLimit: rescore_limit, bits: bits, centering: centering,
                             trainingLimit: training_limit)
        end
      end

      # _VectorIndexUpdate (Reconfigure.VectorIndex)
      module VectorIndexUpdate
        Quantizer = VectorIndexQuantizerUpdate

        def self.hnsw(dynamic_ef_factor: nil, dynamic_ef_min: nil, dynamic_ef_max: nil, ef: nil,
                      flat_search_cutoff: nil, filter_strategy: nil, vector_cache_max_objects: nil, quantizer: nil)
          VectorIndexConfigHNSWUpdate.new(
            dynamicEfMin: dynamic_ef_min,
            dynamicEfMax: dynamic_ef_max,
            dynamicEfFactor: dynamic_ef_factor,
            ef: ef,
            filterStrategy: filter_strategy,
            flatSearchCutoff: flat_search_cutoff,
            vectorCacheMaxObjects: vector_cache_max_objects,
            quantizer: quantizer
          )
        end

        def self.flat(vector_cache_max_objects: nil, quantizer: nil)
          VectorIndexConfigFlatUpdate.new(vectorCacheMaxObjects: vector_cache_max_objects, quantizer: quantizer)
        end

        def self.dynamic(threshold: nil, hnsw: nil, flat: nil, quantizer: nil)
          VectorIndexConfigDynamicUpdate.new(threshold: threshold, hnsw: hnsw, flat: flat, quantizer: quantizer)
        end

        def self.hfresh(max_posting_size_kb: nil, search_probe: nil, quantizer: nil)
          VectorIndexConfigHFreshUpdate.new(maxPostingSizeKB: max_posting_size_kb, searchProbe: search_probe,
                                            quantizer: quantizer)
        end
      end
    end
  end
end
