# frozen_string_literal: true

module Weaviate
  module Collections
    module Config
      # Port of weaviate.collections.classes.config_methods: turns the REST schema JSON
      # returned by Weaviate into the `Weaviate::Classes::Config` output classes.
      #
      # Python's private `_name` functions are public module functions here (without the
      # underscore); Python's `__name` helpers are private.
      module ConfigMethods
        class << self
          def is_primitive(d_type) # rubocop:disable Naming/PredicatePrefix
            first = d_type[0][0]
            first.downcase == first
          end
          alias primitive? is_primitive

          def collection_config_simple_from_json(schema)
            c = ::Weaviate::Classes::Config
            c::CollectionConfigSimple.new(
              name: schema["class"],
              description: schema["description"],
              generative_config: get_generative_config(schema),
              object_ttl_config: get_object_ttl_config(schema),
              properties: schema["properties"].nil? ? [] : properties_from_config(schema),
              references: schema["properties"].nil? ? [] : references_from_config(schema),
              reranker_config: get_rerank_config(schema),
              vectorizer_config: get_vectorizer_config(schema),
              vectorizer: get_vectorizer(schema),
              vector_config: get_vector_config(schema, simple: true)
            )
          end

          def collection_config_from_json(schema)
            c = ::Weaviate::Classes::Config
            iic = schema["invertedIndexConfig"]
            mtc = schema["multiTenancyConfig"] || {}
            rc = schema["replicationConfig"]
            c::CollectionConfig.new(
              name: schema["class"],
              description: schema["description"],
              generative_config: get_generative_config(schema),
              inverted_index_config: c::InvertedIndexConfig.new(
                bm25: c::BM25Config.new(b: iic["bm25"]["b"], k1: iic["bm25"]["k1"]),
                cleanup_interval_seconds: iic["cleanupIntervalSeconds"],
                index_null_state: iic["indexNullState"] == true,
                index_property_length: iic["indexPropertyLength"] == true,
                index_timestamps: iic["indexTimestamps"] == true,
                stopwords: c::StopwordsConfig.new(
                  preset: c::StopwordsPreset.from(iic["stopwords"]["preset"]),
                  additions: iic["stopwords"]["additions"],
                  removals: iic["stopwords"]["removals"]
                ),
                stopword_presets: iic["stopwordPresets"]
              ),
              multi_tenancy_config: c::MultiTenancyConfig.new(
                enabled: mtc.fetch("enabled", false),
                auto_tenant_creation: mtc.fetch("autoTenantCreation", false),
                auto_tenant_activation: mtc.fetch("autoTenantActivation", false)
              ),
              object_ttl_config: get_object_ttl_config(schema),
              properties: schema["properties"].nil? ? [] : properties_from_config(schema),
              references: schema["properties"].nil? ? [] : references_from_config(schema),
              replication_config: c::ReplicationConfig.new(
                factor: rc["factor"],
                async_enabled: rc.fetch("asyncEnabled", false),
                deletion_strategy:
                  if rc.key?("deletionStrategy")
                    c::ReplicationDeletionStrategy.from(rc["deletionStrategy"])
                  else
                    c::ReplicationDeletionStrategy::NO_AUTOMATED_RESOLUTION
                  end,
                async_config: get_async_replication_config(rc["asyncConfig"])
              ),
              reranker_config: get_rerank_config(schema),
              sharding_config: mtc.fetch("enabled", false) ? nil : get_sharding_config(schema["shardingConfig"]),
              vector_index_config: get_vector_index_config(schema),
              vector_index_type: get_vector_index_type(schema),
              vectorizer_config: get_vectorizer_config(schema),
              vectorizer: get_vectorizer(schema),
              vector_config: get_vector_config(schema, simple: false)
            )
          end

          def get_object_ttl_config(schema)
            ttl = schema["objectTtlConfig"]
            return nil unless ttl.is_a?(Hash) && ttl.fetch("enabled", false)

            # Python wraps an int in datetime.timedelta; Ruby keeps the number of seconds.
            time_to_live = ttl["defaultTtl"]
            delete_on = ttl["deleteOn"]
            delete_on = "updateTime" if delete_on == "_lastUpdateTimeUnix"
            delete_on = "creationTime" if delete_on == "_creationTimeUnix"

            ::Weaviate::Classes::Config::ObjectTTLConfig.new(
              enabled: true,
              delete_on: delete_on,
              filter_expired_objects: ttl["filterExpiredObjects"],
              time_to_live: time_to_live
            )
          end

          # Returns a Hash keyed by collection name, sorted by name.
          def collection_configs_from_json(schema)
            configs = schema["classes"].to_h { |s| [s["class"], collection_config_from_json(s)] }
            configs.sort_by { |k, _| k }.to_h
          end

          def collection_configs_simple_from_json(schema)
            configs = schema["classes"].to_h { |s| [s["class"], collection_config_simple_from_json(s)] }
            configs.sort_by { |k, _| k }.to_h
          end

          def text_analyzer_from_config(prop)
            ta = prop["textAnalyzer"]
            return nil if ta.nil?
            # The server normalizes an empty TextAnalyzer to nil, so the only meaningful signal is
            # the presence of one of the configured fields.
            return nil if !ta.key?("asciiFold") && !ta.key?("stopwordPreset")

            ::Weaviate::Classes::Config::TextAnalyzerConfig.new(
              ascii_fold: ta.fetch("asciiFold", false),
              ascii_fold_ignore: ta["asciiFoldIgnore"],
              stopword_preset: ta["stopwordPreset"]
            )
          end

          def nested_properties_from_config(props)
            c = ::Weaviate::Classes::Config
            props.map do |prop|
              c::NestedProperty.new(
                data_type: c::DataType.from(prop["dataType"][0]),
                description: prop["description"],
                index_filterable: prop["indexFilterable"],
                index_searchable: prop["indexSearchable"],
                name: prop["name"],
                nested_properties:
                  prop["nestedProperties"].nil? ? nil : nested_properties_from_config(prop["nestedProperties"]),
                text_analyzer: text_analyzer_from_config(prop),
                tokenization: prop["tokenization"].nil? ? nil : c::Tokenization.from(prop["tokenization"])
              )
            end
          end

          def properties_from_config(schema)
            c = ::Weaviate::Classes::Config
            vectorizer = schema.fetch("vectorizer", "none")
            named = schema.key?("vectorConfig")
            schema["properties"].select { |prop| is_primitive(prop["dataType"]) }.map do |prop|
              module_config = prop["moduleConfig"]
              property_config_class.new(
                data_type: c::DataType.from(prop["dataType"][0]),
                description: prop["description"],
                index_filterable: prop["indexFilterable"],
                index_range_filters: prop.fetch("indexRangeFilters", false),
                index_searchable: prop["indexSearchable"],
                name: prop["name"],
                nested_properties:
                  prop["nestedProperties"].nil? ? nil : nested_properties_from_config(prop["nestedProperties"]),
                text_analyzer: text_analyzer_from_config(prop),
                tokenization: prop["tokenization"].nil? ? nil : c::Tokenization.from(prop["tokenization"]),
                vectorizer_config:
                  if vectorizer != "none" && !module_config.nil?
                    mc = module_config[vectorizer]
                    c::PropertyVectorizerConfig.new(
                      skip: mc.fetch("skip", false),
                      vectorize_property_name: mc.fetch("vectorizePropertyName", false)
                    )
                  end,
                vectorizer_configs:
                  if named
                    (module_config || {}).to_h do |k, v|
                      [k, c::PropertyVectorizerConfig.new(skip: v.fetch("skip", false),
                                                          vectorize_property_name: v.fetch("vectorizePropertyName", false))]
                    end
                  end,
                vectorizer: named ? nil : vectorizer
              )
            end
          end

          def references_from_config(schema)
            schema["properties"].reject { |prop| is_primitive(prop["dataType"]) }.map do |prop|
              reference_property_config_class.new(
                target_collections: prop["dataType"],
                description: prop["description"],
                name: prop["name"]
              )
            end
          end

          private

          # Python `_Property` / `_ReferenceProperty` (public aliases `PropertyConfig` /
          # `ReferencePropertyConfig`, since `Property` / `ReferenceProperty` are the input classes).
          def property_config_class
            ::Weaviate::Classes::Config::PropertyConfig
          end

          def reference_property_config_class
            ::Weaviate::Classes::Config::ReferencePropertyConfig
          end

          def module_config_keys(schema, needle)
            (schema["moduleConfig"] || {}).keys.select { |k| k.include?(needle) }
          end

          # Python: Rerankers(x) falling back to the plain string. Ruby enum members are Strings,
          # so known and unknown values are represented identically.
          def get_rerank_config(schema)
            rerankers = module_config_keys(schema, "reranker")
            return nil unless rerankers.length == 1

            ::Weaviate::Classes::Config::RerankerConfig.new(
              model: schema["moduleConfig"][rerankers[0]],
              reranker: rerankers[0]
            )
          end

          def get_generative_config(schema)
            generators = module_config_keys(schema, "generative")
            return nil unless generators.length == 1

            ::Weaviate::Classes::Config::GenerativeConfig.new(
              generative: generators[0],
              model: schema["moduleConfig"][generators[0]]
            )
          end

          def get_vectorizer_config(schema)
            # NB: Python checks `__is_vectorizer_present(schema) is not None`, which is always true,
            # so only the top-level vectorizer decides. Kept for parity.
            return nil unless schema.fetch("vectorizer", "none") != "none"

            vec_config = schema["moduleConfig"].delete(schema["vectorizer"])
            vectorize_collection_name = vec_config.key?("vectorizeClassName") ? vec_config.delete("vectorizeClassName") : false
            ::Weaviate::Classes::Config::VectorizerConfig.new(
              vectorize_collection_name: vectorize_collection_name,
              model: vec_config,
              vectorizer: schema["vectorizer"]
            )
          end

          def get_vector_index_type(schema)
            return nil unless schema.key?("vectorIndexType")

            ::Weaviate::Classes::Config::VectorIndexType.from(schema["vectorIndexType"])
          end

          def get_quantizer_config(config)
            c = ::Weaviate::Classes::Config
            if config.key?("bq") && config["bq"]["enabled"]
              # values are not present for bq+hnsw
              c::BQConfig.new(cache: config["bq"]["cache"], rescore_limit: config["bq"]["rescoreLimit"])
            elsif config.key?("sq") && config["sq"]["enabled"]
              c::SQConfig.new(rescore_limit: config["sq"]["rescoreLimit"], training_limit: config["sq"]["trainingLimit"])
            elsif config.key?("pq") && config["pq"]["enabled"]
              pq = config["pq"]
              encoder = pq["encoder"] || {}
              c::PQConfig.new(
                internal_bit_compression: pq["bitCompression"],
                segments: pq["segments"],
                centroids: pq["centroids"],
                training_limit: pq["trainingLimit"],
                encoder: c::PQEncoderConfig.new(
                  type_: c::PQEncoderType.from(encoder["type"]),
                  distribution: c::PQEncoderDistribution.from(encoder["distribution"])
                )
              )
            elsif config.key?("rq") && config["rq"]["enabled"]
              rq = config["rq"]
              c::RQConfig.new(cache: rq["cache"], bits: rq["bits"], rescore_limit: rq["rescoreLimit"],
                              centering: rq["centering"], training_limit: rq["trainingLimit"])
            end
          end

          def get_multivector_encoding(config)
            muvera = config["muvera"]
            return nil if muvera.nil? || !muvera["enabled"]

            ::Weaviate::Classes::Config::MuveraConfig.new(
              enabled: muvera["enabled"], ksim: muvera["ksim"], dprojections: muvera["dprojections"],
              repetitions: muvera["repetitions"]
            )
          end

          def get_multivector(config)
            mv = config["multivector"]
            return nil if mv.nil? || !mv["enabled"]

            ::Weaviate::Classes::Config::MultiVectorConfig.new(
              encoding: mv["muvera"].nil? ? nil : get_multivector_encoding(mv),
              aggregation: mv["aggregation"]
            )
          end

          def get_hnsw_config(config)
            c = ::Weaviate::Classes::Config
            c::VectorIndexConfigHNSW.new(
              cleanup_interval_seconds: config.fetch("cleanupIntervalSeconds"),
              distance_metric: c::VectorDistances.from(config["distance"]),
              dynamic_ef_min: config.fetch("dynamicEfMin"),
              dynamic_ef_max: config.fetch("dynamicEfMax"),
              dynamic_ef_factor: config.fetch("dynamicEfFactor"),
              ef: config.fetch("ef"),
              ef_construction: config.fetch("efConstruction"),
              filter_strategy:
                if config.key?("filterStrategy")
                  c::VectorFilterStrategy.from(config["filterStrategy"])
                else
                  c::VectorFilterStrategy::SWEEPING
                end,
              flat_search_cutoff: config.fetch("flatSearchCutoff"),
              max_connections: config.fetch("maxConnections"),
              quantizer: get_quantizer_config(config),
              skip: config.fetch("skip"),
              vector_cache_max_objects: config.fetch("vectorCacheMaxObjects"),
              multi_vector: get_multivector(config)
            )
          end

          def get_hfresh_config(config)
            c = ::Weaviate::Classes::Config
            c::VectorIndexConfigHFresh.new(
              distance_metric: c::VectorDistances.from(config["distance"]),
              max_posting_size_kb: config.fetch("maxPostingSizeKB"),
              replicas: config.fetch("replicas"),
              search_probe: config.fetch("searchProbe"),
              quantizer: get_quantizer_config(config),
              multi_vector: get_multivector(config)
            )
          end

          def get_flat_config(config)
            c = ::Weaviate::Classes::Config
            c::VectorIndexConfigFlat.new(
              distance_metric: c::VectorDistances.from(config.fetch("distance")),
              quantizer: get_quantizer_config(config),
              vector_cache_max_objects: config.fetch("vectorCacheMaxObjects"),
              multi_vector: get_multivector(config)
            )
          end

          def get_vector_index_config(schema)
            return nil unless schema.key?("vectorIndexConfig")

            c = ::Weaviate::Classes::Config
            vic = schema["vectorIndexConfig"]
            case schema["vectorIndexType"]
            when "hnsw" then get_hnsw_config(vic)
            when "flat" then get_flat_config(vic)
            when "dynamic"
              c::VectorIndexConfigDynamic.new(
                distance_metric: c::VectorDistances.from(vic.fetch("distance")),
                threshold: vic["threshold"],
                hnsw: get_hnsw_config(vic.fetch("hnsw")),
                flat: get_flat_config(vic.fetch("flat"))
              )
            when "hfresh" then get_hfresh_config(vic)
            end
          end

          def get_vector_config(schema, simple:) # rubocop:disable Lint/UnusedMethodArgument
            return nil unless schema.key?("vectorConfig")

            c = ::Weaviate::Classes::Config
            schema["vectorConfig"].to_h do |name, named_vector|
              vectorizer = named_vector["vectorizer"].keys
              raise "expected exactly one vectorizer for named vector #{name.inspect}" unless vectorizer.length == 1

              vectorizer_str = vectorizer[0].to_s
              vec_config = named_vector["vectorizer"][vectorizer_str] || {}
              props = vec_config.delete("properties")

              vector_index_config = get_vector_index_config(named_vector)
              if vector_index_config.nil?
                # A vector whose index was dropped with `collection.config.delete_vector_index()` is
                # returned as `vectorIndexType: "none"` without any `vectorIndexConfig`.
                if named_vector["vectorIndexType"] == c::VectorIndexType::NONE
                  vector_index_config = c::VectorIndexConfigNone.new
                elsif named_vector.key?("vectorIndexConfig")
                  raise ::Weaviate::Exceptions::SchemaValidationError,
                        "Named vector #{::Weaviate::Util.py_repr(name)} has an unknown vectorIndexType " \
                        "#{::Weaviate::Util.py_repr(named_vector["vectorIndexType"])}; upgrade the client to a version " \
                        "that supports it"
                else
                  raise ::Weaviate::Exceptions::SchemaValidationError,
                        "Named vector #{::Weaviate::Util.py_repr(name)} has vectorIndexType " \
                        "#{::Weaviate::Util.py_repr(named_vector["vectorIndexType"])} but no vectorIndexConfig in the " \
                        "schema returned by Weaviate"
                end
              end

              [name, c::NamedVectorConfig.new(
                vectorizer: c::NamedVectorizerConfig.new(vectorizer: vectorizer_str, model: vec_config,
                                                         source_properties: props),
                vector_index_config: vector_index_config
              )]
            end
          end

          def get_vectorizer(schema)
            return nil if schema.key?("vectorConfig")
            # A named-vector collection whose vectors were all dropped comes back with neither a
            # `vectorConfig` block nor a top-level `vectorizer`.
            return nil unless schema.key?("vectorizer")

            schema["vectorizer"].to_s
          end

          def get_sharding_config(sc)
            ::Weaviate::Classes::Config::ShardingConfig.new(
              virtual_per_physical: sc.fetch("virtualPerPhysical"),
              desired_count: sc.fetch("desiredCount"),
              actual_count: sc.fetch("actualCount"),
              desired_virtual_count: sc.fetch("desiredVirtualCount"),
              actual_virtual_count: sc.fetch("actualVirtualCount"),
              key: sc.fetch("key"),
              strategy: sc.fetch("strategy"),
              function: sc.fetch("function")
            )
          end

          def get_async_replication_config(async_cfg)
            return nil if async_cfg.nil? || async_cfg.empty?

            ::Weaviate::Classes::Config::AsyncReplicationConfig.new(
              max_workers: async_cfg["maxWorkers"],
              hashtree_height: async_cfg["hashtreeHeight"],
              frequency: async_cfg["frequency"],
              frequency_while_propagating: async_cfg["frequencyWhilePropagating"],
              alive_nodes_checking_frequency: async_cfg["aliveNodesCheckingFrequency"],
              logging_frequency: async_cfg["loggingFrequency"],
              diff_batch_size: async_cfg["diffBatchSize"],
              diff_per_node_timeout: async_cfg["diffPerNodeTimeout"],
              pre_propagation_timeout: async_cfg["prePropagationTimeout"],
              propagation_timeout: async_cfg["propagationTimeout"],
              propagation_limit: async_cfg["propagationLimit"],
              propagation_delay: async_cfg["propagationDelay"],
              propagation_concurrency: async_cfg["propagationConcurrency"],
              propagation_batch_size: async_cfg["propagationBatchSize"]
            )
          end
        end
      end
    end
  end
end
