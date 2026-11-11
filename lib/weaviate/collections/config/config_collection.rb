# frozen_string_literal: true

module Weaviate
  module Collections
    module Config
      # Minimal port of weaviate.validator._validate_input for the config / collections
      # namespaces. +expected+ entries are classes, `:bool`, or `[Class]` (an Array whose
      # elements are all instances of Class).
      module ArgumentValidation
        module_function

        def validate_input(name, value, *expected)
          return if expected.any? { |exp| valid?(exp, value) }

          names = expected.map { |exp| exp.is_a?(Array) ? "Array[#{exp.map(&:to_s).join(", ")}]" : exp.to_s }
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "Argument '#{name}' must be one of: [#{names.join(", ")}], but got #{value.class}"
        end

        def valid?(expected, value)
          case expected
          when :bool then [true, false].include?(value)
          when nil then value.nil?
          when Array then value.is_a?(Array) && value.all? { |v| expected.any? { |e| valid?(e, v) } }
          when Module then value.is_a?(expected)
          else false
          end
        end
      end

      # Port of weaviate.collections.config (sync `_ConfigCollection`): the
      # `collection.config` namespace.
      class ConfigCollection
        include ArgumentValidation

        def self.any_property_has_text_analyzer(properties)
          Array(properties).any? { |p| property_has_text_analyzer(p) }
        end

        def self.property_has_text_analyzer(prop)
          return false unless prop.is_a?(::Weaviate::Classes::Config::Property)
          return true unless read_attr(prop, :textAnalyzer, :text_analyzer).nil?

          nested = read_attr(prop, :nestedProperties, :nested_properties)
          return false if nested.nil?

          (nested.is_a?(Array) ? nested : [nested]).any? { |np| property_has_text_analyzer(np) }
        end

        # Python pydantic models expose camelCase fields with snake_case aliases; accept either.
        def self.read_attr(obj, *names)
          name = names.find { |n| obj.respond_to?(n) }
          name.nil? ? nil : obj.public_send(name)
        end

        def initialize(connection:, name:, tenant: nil)
          @connection = connection
          @name = name
          @tenant = tenant
        end

        # Get the configuration for this collection from Weaviate.
        # Returns a CollectionConfig, or a CollectionConfigSimple when +simple+ is true.
        def get(simple: false)
          validate_input("simple", simple, :bool)
          schema = get_raw
          return ConfigMethods.collection_config_simple_from_json(schema) if simple

          ConfigMethods.collection_config_from_json(schema)
        end

        # Update the configuration for this collection in Weaviate. Use
        # `Weaviate::Classes::Config::Reconfigure` to build the arguments.
        def update(description: nil, property_descriptions: nil, inverted_index_config: nil,
                   multi_tenancy_config: nil, object_ttl_config: nil, replication_config: nil,
                   vector_index_config: nil, vectorizer_config: nil, vector_config: nil,
                   generative_config: nil, reranker_config: nil)
          c = ::Weaviate::Classes::Config
          ::Weaviate::Warnings.vector_index_config_in_config_update unless vector_index_config.nil?
          if !vectorizer_config.nil? && !vector_index_update?(vectorizer_config)
            ::Weaviate::Warnings.vectorizer_config_in_config_update
          end
          if !inverted_index_config.nil? &&
             !self.class.read_attr(inverted_index_config, :stopwordPresets, :stopword_presets).nil? &&
             !@connection.weaviate_version.is_at_least(1, 37, 0)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
              "InvertedIndexConfig stopword_presets", @connection.weaviate_version.to_s, "1.37.0"
            )
          end
          begin
            config = c::CollectionConfigUpdate.new(
              description: description,
              property_descriptions: property_descriptions,
              inverted_index_config: inverted_index_config,
              replication_config: replication_config,
              vector_index_config: vector_index_config,
              vectorizer_config: vectorizer_config,
              object_ttl_config: object_ttl_config,
              multi_tenancy_config: multi_tenancy_config,
              generative_config: generative_config,
              reranker_config: reranker_config,
              vector_config: vector_config
            )
          rescue ArgumentError, TypeError => e
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Invalid collection config update parameters. #{e.message}".strip
          end

          schema = config.merge_with_existing(get_raw)
          @connection.put(
            "/schema/#{@name}",
            weaviate_object: schema,
            error_msg: "Collection configuration may not have been updated.",
            status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Update collection configuration")
          )
          nil
        end

        # Get the statuses of the shards of this collection (only the tenant's shard when the
        # collection was obtained with `.with_tenant`). Returns an Array of ShardStatus.
        def get_shards
          params = @tenant.nil? || @tenant.to_s.empty? ? nil : { "tenant" => @tenant }
          res = @connection.get("/schema/#{@name}/shards", params: params,
                                                          error_msg: "Shard statuses could not be retrieved.")
          shards = ::Weaviate::Util.decode_json_response_list(res, "get shards")
          shards.map do |shard|
            ::Weaviate::Classes::Config::ShardStatus.new(
              name: shard["name"],
              status: shard.fetch("status", ""),
              vector_queue_size: shard["vectorQueueSize"],
              per_node_status: shard["per_node_status"]
            )
          end
        end

        # Update the status of one or all shards of this collection.
        # +status+ is "READY" or "READONLY"; +shard_names+ a String, an Array, or nil for all shards.
        # Returns a Hash of shard name => new status.
        def update_shards(status, shard_names: nil)
          shard_names =
            if shard_names.nil?
              get_shards.map(&:name)
            elsif shard_names.is_a?(String)
              [shard_names]
            else
              shard_names
            end
          shard_names.to_h { |shard_name| update_shard(shard_name, status) }
        end

        # Add a property to the collection in Weaviate.
        def add_property(prop)
          validate_input("prop", prop, ::Weaviate::Classes::Config::Property)
          if property_exists(prop.name)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Property with name '#{prop.name}' already exists in collection '#{@name}'."
          end
          add_property_raw(prop)
        end

        # Add a reference to the collection in Weaviate.
        def add_reference(ref)
          c = ::Weaviate::Classes::Config
          validate_input("ref", ref, c::ReferenceProperty, c::ReferencePropertyMultiTarget)
          if reference_exists(ref.name)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Reference with name '#{ref.name}' already exists in collection '#{@name}'."
          end
          add_property_raw(ref)
        end

        # Add a vector (or several) to the collection in Weaviate.
        def add_vector(vector_config:)
          c = ::Weaviate::Classes::Config
          validate_input("vector_config", vector_config, c::NamedVectorConfigCreate, c::VectorConfigCreate,
                         [c::NamedVectorConfigCreate], [c::VectorConfigCreate])
          if vector_config.is_a?(Array)
            vector_config.each do |vc|
              ::Weaviate::Warnings.named_vector_syntax_in_config_add_vector(vc.name) if vc.is_a?(c::NamedVectorConfigCreate)
              if vc.name.nil?
                raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                      "The configured vector must have a name when adding it to a collection."
              end
            end
          end
          if vector_config.is_a?(c::NamedVectorConfigCreate)
            ::Weaviate::Warnings.named_vector_syntax_in_config_add_vector(vector_config.name)
            vector_config = [vector_config]
          end
          vector_config = [vector_config] if vector_config.is_a?(c::VectorConfigCreate)

          schema = get_raw
          schema["vectorConfig"] = {} unless schema.key?("vectorConfig")
          vector_config.each { |vector| schema["vectorConfig"][vector.name] = vector.to_dict }
          @connection.put(
            "/schema/#{@name}",
            weaviate_object: schema,
            error_msg: "Collection configuration may not have been updated.",
            status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Update collection configuration")
          )
          nil
        end

        # Delete a property index from the collection in Weaviate. Destructive: the index must be
        # regenerated to be used again. +index_name+ is e.g. "filterable", "searchable", "rangeFilters".
        def delete_property_index(property_name, index_name:)
          validate_input("property_name", property_name, String)
          validate_input("index_name", index_name, String)
          path = "/schema/#{::Weaviate::Util.capitalize_first_letter(@name)}/properties/#{property_name}/index/#{index_name}"
          res = @connection.delete(path, error_msg: "Property may not exist",
                                         status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200],
                                                                                                    error: "property exists"))
          res.status_code == 200
        end

        # Delete the index of a named vector of the collection in Weaviate. Destructive and
        # irreversible; applied asynchronously by the server.
        def delete_vector_index(vector_name)
          validate_input("vector_name", vector_name, String)
          path = "/schema/#{::Weaviate::Util.capitalize_first_letter(@name)}/vectors/#{vector_name}/index"
          @connection.delete(path, error_msg: "Vector index may not have been deleted",
                                   status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200],
                                                                                              error: "delete vector index"))
          nil
        end

        def inspect = "#<#{self.class.name} name=#{@name.inspect} tenant=#{@tenant.inspect}>"

        private

        def get_raw
          res = @connection.get(
            "/schema/#{@name}",
            error_msg: "Collection configuration could not be retrieved.",
            status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Get collection configuration")
          )
          res.json
        end

        def vector_index_update?(value)
          c = ::Weaviate::Classes::Config
          %i[VectorIndexConfigHNSWUpdate VectorIndexConfigFlatUpdate VectorIndexConfigDynamicUpdate
             VectorIndexConfigHFreshUpdate].any? { |n| c.const_defined?(n) && value.is_a?(c.const_get(n)) }
        end

        def add_property_raw(additional_property)
          if additional_property.is_a?(::Weaviate::Classes::Config::Property) &&
             self.class.property_has_text_analyzer(additional_property) &&
             !@connection.weaviate_version.is_at_least(1, 37, 0)
            raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
              "Property text_analyzer (asciiFold)", @connection.weaviate_version.to_s, "1.37.0"
            )
          end
          obj = additional_property.to_dict
          schema = get_raw

          modconf = {}
          modconf["skip"] = obj.delete("skip_vectorization") if obj.key?("skip_vectorization")
          modconf["vectorizePropertyName"] = obj.delete("vectorize_property_name") if obj.key?("vectorize_property_name")

          module_config = schema["moduleConfig"] || {}
          legacy_vectorizer = module_config.keys.map(&:to_s).reject { |k| k.include?("generative") || k.include?("reranker") }
          obj["moduleConfig"] = { legacy_vectorizer[0] => modconf } if !legacy_vectorizer.empty? && !modconf.empty?

          vector_config = schema["vectorConfig"] || {}
          unless vector_config.empty?
            obj["moduleConfig"] = vector_config.values.to_h { |conf| [conf["vectorizer"].keys.last, modconf] }
          end

          @connection.post(
            "/schema/#{@name}/properties",
            weaviate_object: obj,
            error_msg: "Property may not have been added properly.",
            status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Add property to collection")
          )
          nil
        end

        def property_exists(property_name)
          conf = ConfigMethods.collection_config_simple_from_json(get_raw)
          conf.properties.any? { |prop| prop.name == property_name }
        end

        def reference_exists(reference_name)
          conf = ConfigMethods.collection_config_simple_from_json(get_raw)
          conf.references.any? { |ref| ref.name == reference_name }
        end

        def update_shard(shard_name, status)
          res = @connection.put("/schema/#{@name}/shards/#{shard_name}",
                                weaviate_object: { "status" => status },
                                error_msg: "shard '#{shard_name}' may not have been updated.")
          shard = ::Weaviate::Util.decode_json_response_dict(res, "Update shard '#{shard_name}' status")
          [shard_name, shard["status"]]
        end
      end
    end
  end
end
