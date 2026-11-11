# frozen_string_literal: true

module Weaviate
  module Collections
    # Port of weaviate.collections.collections (sync `_Collections`): the
    # `client.collections` namespace.
    class Collections
      def initialize(connection)
        @connection = connection
      end

      # Return a Collection object for +name+. Sends no request to Weaviate.
      # (Python's `data_model_properties` / `data_model_references` generics are dropped.)
      def use(name, skip_argument_validation: false)
        unless skip_argument_validation
          ::Weaviate::Collections::Config::ArgumentValidation.validate_input("name", name, String)
        end
        name = ::Weaviate::Util.capitalize_first_letter(name)
        ::Weaviate::Collections::Collection.new(@connection, name, validate_arguments: !skip_argument_validation,
                                                                   consistency_level: nil, tenant: nil)
      end

      # Same as #use.
      def get(name, skip_argument_validation: false)
        use(name, skip_argument_validation: skip_argument_validation)
      end

      # Create a collection in Weaviate and return the Collection object for it. Use
      # `Weaviate::Classes::Config::Configure` to build the configuration arguments.
      def create(name, description: nil, generative_config: nil, inverted_index_config: nil,
                 multi_tenancy_config: nil, object_ttl_config: nil, properties: nil, references: nil,
                 replication_config: nil, reranker_config: nil, sharding_config: nil, vector_index_config: nil,
                 vectorizer_config: nil, vector_config: nil, skip_argument_validation: false)
        c = ::Weaviate::Classes::Config
        ::Weaviate::Warnings.vectorizer_config_in_config_create unless vectorizer_config.nil?
        ::Weaviate::Warnings.vector_index_config_in_config_create unless vector_index_config.nil?
        if !properties.nil? && ::Weaviate::Collections::Config::ConfigCollection.any_property_has_text_analyzer(properties) &&
           !@connection.weaviate_version.is_at_least(1, 37, 0)
          raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
            "Property text_analyzer (asciiFold / stopword_preset)", @connection.weaviate_version.to_s, "1.37.0"
          )
        end
        if !inverted_index_config.nil? &&
           !::Weaviate::Collections::Config::ConfigCollection.read_attr(inverted_index_config, :stopwordPresets,
                                                                         :stopword_presets).nil? &&
           !@connection.weaviate_version.is_at_least(1, 37, 0)
          raise ::Weaviate::Exceptions::WeaviateUnsupportedFeatureError.new(
            "InvertedIndexConfig stopword_presets", @connection.weaviate_version.to_s, "1.37.0"
          )
        end
        begin
          config = c::CollectionConfigCreate.new(
            description: description,
            generative_config: generative_config,
            inverted_index_config: inverted_index_config,
            multi_tenancy_config: multi_tenancy_config,
            name: name,
            properties: properties,
            references: references,
            object_ttl_config: object_ttl_config,
            replication_config: replication_config,
            reranker_config: reranker_config,
            sharding_config: sharding_config,
            vectorizer_config: vectorizer_config,
            vector_config: vector_config,
            vector_index_config: vector_index_config
          )
        rescue ArgumentError, TypeError => e
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid collection config create parameters: #{e.message}"
        end

        # Servers >= 1.37.5 apply DEFAULT_VECTOR_INDEX_TYPE to named-vector configs that omit
        # `vectorIndexType`; older servers reject the empty field, so for them we keep emitting
        # the client-side HNSW default.
        emit_default_vector_index_type = !@connection.weaviate_version.is_at_least(1, 37, 5)
        create_raw(config.to_dict(emit_default_vector_index_type: emit_default_vector_index_type),
                   skip_argument_validation: skip_argument_validation)
      end

      # Create a collection from a raw (REST-shaped) configuration Hash. Vector entries whose
      # index was dropped (`vectorIndexType: "none"`) are skipped with a warning; if every
      # entry was dropped a WeaviateInvalidInputError is raised.
      def create_from_dict(config)
        create_raw(config)
      end

      # Create a collection from a CollectionConfig (e.g. one returned by #export_config).
      def create_from_config(config)
        # A config with neither named vectors nor a legacy vectorizer can only come from exporting
        # a collection whose vectors were all dropped and cleaned up.
        if config.vector_config.nil? && config.vectorizer.nil?
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "Collection config #{::Weaviate::Util.py_repr(config.name)} has no vector config left; its vectors were " \
                "dropped with collection.config.delete_vector_index() and removed by the drop's " \
                "cleanup. Creating it would make the server apply its default legacy vector index " \
                "instead. Give the config at least one vector before creating the collection."
        end
        create_from_dict(config.to_dict)
      end

      # Delete one collection (String) or several (Array of String). Deleting a collection that
      # does not exist is a no-op.
      def delete(name)
        ::Weaviate::Collections::Config::ArgumentValidation.validate_input("name", name, String, [String])
        if name.is_a?(String)
          delete_one(::Weaviate::Util.capitalize_first_letter(name))
        else
          name.each { |n| delete_one(::Weaviate::Util.capitalize_first_letter(n)) }
        end
        nil
      end

      # Delete every collection in the Weaviate instance. Use with caution.
      def delete_all
        delete(list_all.keys)
      end

      # Whether a collection named +name+ exists.
      def exists(name)
        ::Weaviate::Collections::Config::ArgumentValidation.validate_input("name", name, String)
        raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Collection name cannot be an empty string." if name == ""

        res = @connection.get("/schema/#{::Weaviate::Util.capitalize_first_letter(name)}",
                              error_msg: "Collection may not exist.",
                              status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200, 404],
                                                                                         error: "collection exists"))
        res.status_code == 200
      end
      alias exists? exists

      # Export the configuration of collection +name+ as a CollectionConfig.
      def export_config(name)
        res = @connection.get("/schema/#{::Weaviate::Util.capitalize_first_letter(name)}",
                              error_msg: "Could not export collection config")
        data = ::Weaviate::Util.decode_json_response_dict(res, "Get schema export")
        ::Weaviate::Collections::Config::ConfigMethods.collection_config_from_json(data)
      end

      # List the configurations of all collections, as a Hash of name => CollectionConfigSimple
      # (or CollectionConfig when +simple+ is false), sorted by name.
      def list_all(simple: true)
        ::Weaviate::Collections::Config::ArgumentValidation.validate_input("simple", simple, :bool)
        res = @connection.get("/schema", error_msg: "Get all collections")
        data = ::Weaviate::Util.decode_json_response_dict(res, "Get schema all")
        if simple
          ::Weaviate::Collections::Config::ConfigMethods.collection_configs_simple_from_json(data)
        else
          ::Weaviate::Collections::Config::ConfigMethods.collection_configs_from_json(data)
        end
      end

      def inspect = "#<#{self.class.name}>"

      private

      def create_raw(config, skip_argument_validation: false)
        config = without_dropped_vectors(config)
        res = @connection.post(
          "/schema",
          weaviate_object: config,
          error_msg: "Collection may not have been created properly.",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Create collection")
        )
        use(res.json["class"], skip_argument_validation: skip_argument_validation)
      end

      def without_dropped_vectors(config)
        vector_config = config["vectorConfig"]
        return config unless vector_config.is_a?(Hash)

        none = ::Weaviate::Classes::Config::VectorIndexType::NONE
        dropped = vector_config.select { |_, vc| vc.is_a?(Hash) && vc["vectorIndexType"] == none }.keys
        return config if dropped.empty?

        remaining = vector_config.except(*dropped)
        if remaining.empty?
          raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                "Every vector config in this collection (#{::Weaviate::Util.py_str(dropped)}) has vectorIndexType 'none' " \
                "(its index was dropped with collection.config.delete_vector_index()). Creating " \
                "the collection without them would make the server apply its default legacy " \
                "vector index instead. Give at least one vector a real index config before " \
                "creating the collection."
        end
        ::Weaviate::Warnings.create_skips_vectors_without_index(::Weaviate::Util.py_str(dropped))
        config.merge("vectorConfig" => remaining)
      end

      def delete_one(name)
        @connection.delete("/schema/#{name}",
                           error_msg: "Collection may not have been deleted properly.",
                           status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Delete collection"))
      end
    end
  end
end
