# frozen_string_literal: true

require_relative "base"
require_relative "vectorizers"
require_relative "named_vectors"

# Port of weaviate.collections.classes.config_vectors.
module Weaviate
  module Classes
    module Config
      # Port of VectorConfigCreate (alias _VectorConfigCreate).
      class VectorConfigCreate < ConfigCreateModel
        include VectorConfigCreateBehaviour

        attribute :name, default: nil
        attribute :properties, default: nil
        attribute :vectorizer
        attribute :vectorIndexType, default: -> { ::Weaviate::Classes::Config::VectorIndexType::HNSW }
        attribute :vectorIndexConfig, default: nil

        def after_initialize
          super
          return if name.nil? || name.is_a?(String)

          raise ::Weaviate::Classes::Config::ValidationError,
                "#{self.class.name}: name must be a String or nil, got #{name.inspect}"
        end
      end

      # Port of VectorConfigUpdate (alias _VectorConfigUpdate).
      class VectorConfigUpdate < ConfigUpdateModel
        include VectorConfigUpdateBehaviour

        attribute :name
        attribute :vectorIndexConfig
      end

      # Port of _IndexWrappers: attach a quantizer / multi-vector config to a (possibly
      # missing) vector index config.
      module IndexWrappers
        def self.hnsw(quantizer: nil, multivector: nil)
          ::Weaviate::Classes::Config::VectorIndexConfigHNSWCreate.new(
            cleanupIntervalSeconds: nil,
            distance: nil,
            dynamicEfMin: nil,
            dynamicEfMax: nil,
            dynamicEfFactor: nil,
            efConstruction: nil,
            ef: nil,
            filterStrategy: nil,
            flatSearchCutoff: nil,
            maxConnections: nil,
            vectorCacheMaxObjects: nil,
            quantizer: quantizer,
            multivector: multivector
          )
        end

        def self.hfresh(quantizer:)
          ::Weaviate::Classes::Config::VectorIndexConfigHFreshCreate.new(
            maxPostingSizeKB: nil,
            replicas: nil,
            searchProbe: nil,
            quantizer: quantizer,
            multivector: nil,
            distance: nil
          )
        end

        def self.flat(quantizer:)
          ::Weaviate::Classes::Config::VectorIndexConfigFlatCreate.new(
            distance: nil,
            vectorCacheMaxObjects: nil,
            quantizer: quantizer,
            multivector: nil
          )
        end

        def self.single(vector_index_config, quantizer)
          unless quantizer.nil?
            if vector_index_config.nil?
              vector_index_config = hnsw(quantizer: quantizer)
            elsif vector_index_config.is_a?(::Weaviate::Classes::Config::VectorIndexConfigDynamicCreate)
              if vector_index_config.hnsw.nil?
                vector_index_config.hnsw = hnsw(quantizer: quantizer)
              else
                vector_index_config.hnsw.quantizer = quantizer
              end
              if vector_index_config.flat.nil?
                vector_index_config.flat = flat(quantizer: quantizer)
              else
                vector_index_config.flat.quantizer = quantizer
              end
            else
              vector_index_config.quantizer = quantizer
            end
          end
          vector_index_config
        end

        def self.multi(vector_index_config, quantizer, multi_vector_config, encoding)
          if multi_vector_config.nil?
            multi_vector_config = ::Weaviate::Classes::Config::MultiVectorConfigCreate.new(aggregation: nil, encoding: nil)
          end
          multi_vector_config.encoding = encoding unless encoding.nil?
          if vector_index_config.nil?
            vector_index_config = hnsw(multivector: multi_vector_config)
          else
            vector_index_config.multivector = multi_vector_config
          end
          single(vector_index_config, quantizer)
        end
      end

      # Port of _MultiVectors (exposed as `Configure::MultiVectors`).
      module MultiVectors
        # Create a multi-vector using no vectorizer. You will need to provide the vectors yourself.
        #
        # Args:
        #     name: The name of the vector.
        #     encoding: The type of multi-vector encoding to use in the vector index. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     multi_vector_config: The configuration for the multi-vector index. Use `wvc.config.Configure.VectorIndex.MultiVector` to create a multi-vector configuration. None by default
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.self_provided(
          name: nil,
          encoding: nil,
          quantizer: nil,
          multi_vector_config: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: VectorizerConfigCreate.new(vectorizer: Vectorizers::NONE),
            vector_index_config: IndexWrappers.multi(vector_index_config, quantizer, multi_vector_config, encoding)
          )
        end

        # Create a multi-vector using the `text2colbert-jinaai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/colbert) for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     encoding: The type of multi-vector encoding to use in the vector index. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimensions: Number of dimensions. Applicable to v3 OpenAI models only. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     encoding: The type of multi-vector encoding to use in the vector index. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     multi_vector_config: The configuration for the multi-vector index. Use `wvc.config.Configure.VectorIndex.MultiVector` to create a multi-vector configuration. None by default
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_jinaai(
          name: nil,
          encoding: nil,
          quantizer: nil,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          multi_vector_config: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vector_index_config: IndexWrappers.multi(vector_index_config, quantizer, multi_vector_config, encoding),
            vectorizer: Text2ColbertJinaAIConfig.new(
              model: model,
              dimensions: dimensions,
              vectorizeClassName: vectorize_collection_name
            )
          )
        end

        # Create a vector using the `multi2multivec-jinaai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     encoding: The type of multi-vector encoding to use in the vector index. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     multi_vector_config: The configuration for the multi-vector index. Use `wvc.config.Configure.VectorIndex.MultiVector` to create a multi-vector configuration. None by default
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_jinaai(
          name: nil,
          encoding: nil,
          quantizer: nil,
          base_url: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          multi_vector_config: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2MultiVecJinaConfig.new(
              baseURL: base_url,
              model: model,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.multi(vector_index_config, quantizer, multi_vector_config, encoding)
          )
        end

        # Create a vector using the `multi2multivec-weaviate` module.
        #
        # Args:
        #     image_field: The image field to use in vectorization.
        #     name: The name of the vector.
        #     encoding: The type of multi-vector encoding to use in the vector index. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     multi_vector_config: The configuration for the multi-vector index. Use `wvc.config.Configure.VectorIndex.MultiVector` to create a multi-vector configuration. None by default
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_weaviate(
          image_field:,
          name: nil,
          encoding: nil,
          quantizer: nil,
          base_url: nil,
          model: nil,
          multi_vector_config: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2MultiVecWeaviateConfig.new(
              baseURL: base_url,
              model: model,
              imageFields: Vectorizer.map_multi2vec_fields([image_field]),
              textFields: nil
            ),
            vector_index_config: IndexWrappers.multi(vector_index_config, quantizer, multi_vector_config, encoding)
          )
        end
      end


      # Port of _Vectors (exposed as `Configure::Vectors`).
      module Vectors
        # Create a vector using no vectorizer. You will need to provide the vectors yourself.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.self_provided(name: nil, quantizer: nil, vector_index_config: nil)
          VectorConfigCreate.new(
            name: name,
            vectorizer: VectorizerConfigCreate.new(vectorizer: Vectorizers::NONE),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using a custom module that is not currently supported by the SDK.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     module_name: The name of the custom module to use.
        #     module_config: The configuration of the custom module to use.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.custom(
          name: nil,
          quantizer: nil,
          module_name:,
          module_config: nil,
          source_properties: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: VectorizerCustomConfig.new(
              vectorizer: EnumLikeStr.new(string: module_name),
              module_config: module_config
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-cohere` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of output dimensions. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_cohere(
          name: nil,
          quantizer: nil,
          base_url: nil,
          model: nil,
          dimensions: nil,
          truncate: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecCohereConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: dimensions,
              truncate: truncate,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec_cohere` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of output dimensions. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_cohere(
          name: nil,
          quantizer: nil,
          base_url: nil,
          image_fields: nil,
          model: nil,
          dimensions: nil,
          text_fields: nil,
          truncate: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecCohereConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: dimensions,
              truncate: truncate,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec_contextionary` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/text2vec-contextionary)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_contextionary(
          name: nil,
          quantizer: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          ::Weaviate::Warnings.emit(
            "The contextionary model is old and not recommended for use. If you are looking for a local, lightweight model try the new text2vec-model2vec module instead."
          )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecContextionaryConfig.new(vectorizeClassName: vectorize_collection_name),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec_model2vec` module.
        #
        # See the [documentation](https://docs.weaviate.io/weaviate/model-providers/model2vec)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     inference_url: The inferenceUrl to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_model2vec(
          name: nil,
          quantizer: nil,
          source_properties: nil,
          vector_index_config: nil,
          inference_url: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecModel2VecConfig.new(
              vectorizeClassName: vectorize_collection_name,
              inferenceUrl: inference_url
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-databricks` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/databricks/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     endpoint: The endpoint to use.
        #     instruction: The instruction strategy to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_databricks(
          name: nil,
          quantizer: nil,
          endpoint:,
          instruction: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecDatabricksConfig.new(
              endpoint: endpoint,
              instruction: instruction,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-mistral` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/mistral/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_mistral(
          name: nil,
          quantizer: nil,
          base_url: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecMistralConfig.new(
              baseURL: base_url,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-digitalocean` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/digitalocean/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default of `https://inference.do-ai.run`.
        #     model: The model to use, e.g. `qwen3-embedding-0.6b`. This is a required field on the server.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_digitalocean(
          name: nil,
          quantizer: nil,
          base_url: nil,
          model:,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecDigitalOceanConfig.new(
              baseURL: base_url,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-morph` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/morph/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     endpoint: The API path to append to `base_url`, e.g. `/api/v3/embeddings`. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_morph(
          name: nil,
          quantizer: nil,
          base_url: nil,
          model: nil,
          endpoint: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecMorphConfig.new(
              baseURL: base_url,
              model: model,
              endpoint: endpoint,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-ollama` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/ollama/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     api_endpoint: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #         Docker users may need to specify an alias, such as `http://host.docker.internal:11434` so that the container can access the host machine.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_ollama(
          name: nil,
          quantizer: nil,
          api_endpoint: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecOllamaConfig.new(
              apiEndpoint: api_endpoint,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-openai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of dimensions. Applicable to v3 OpenAI models only. Defaults to `None`, which uses the server-defined default.
        #     endpoint: The API path to append to `base_url`, e.g. `/api/v3/embeddings`. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     model_version: The model version to use. Defaults to `None`, which uses the server-defined default.
        #     type_: The type of model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_openai(
          name: nil,
          quantizer: nil,
          base_url: nil,
          dimensions: nil,
          endpoint: nil,
          model: nil,
          model_version: nil,
          type_: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecOpenAIConfig.new(
              baseURL: base_url,
              model: model,
              modelVersion: model_version,
              type_: type_,
              vectorizeClassName: vectorize_collection_name,
              dimensions: dimensions,
              endpoint: endpoint
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-aws` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     endpoint: The endpoint to use. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use, REQUIRED.
        #     region: The AWS region to run the model from, REQUIRED.
        #     service: The AWS service to use. Defaults to `bedrock`.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_aws(
          name: nil,
          quantizer: nil,
          endpoint: nil,
          model:,
          region:,
          service: "bedrock",
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          dimensions: nil
        )
          ::Weaviate::Warnings.emit(
            "`text2vec_aws` is deprecated and will be removed after Q3 '26. Use a service-specific method instead, such as `text2vec_aws_bedrock`."
          )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecAWSConfig.new(
              model: model,
              endpoint: endpoint,
              region: region,
              service: service,
              vectorizeClassName: vectorize_collection_name,
              targetModel: nil,
              targetVariant: nil,
              dimensions: dimensions
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-aws` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     model: The model to use, REQUIRED.
        #     region: The AWS region to run the model from, REQUIRED.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_aws_bedrock(
          name: nil,
          model:,
          region:,
          quantizer: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          dimensions: nil
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecAWSConfig.new(
              model: model,
              endpoint: nil,
              region: region,
              service: "bedrock",
              vectorizeClassName: vectorize_collection_name,
              targetModel: nil,
              targetVariant: nil,
              dimensions: dimensions
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-aws` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     endpoint: The endpoint to use, REQUIRED.
        #     region: The AWS region to run the model from, REQUIRED.
        #     target_model: The target model to use. Defaults to `None`, which uses the server-defined default.
        #     target_variant: The target variant to use. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_aws_sagemaker(
          name: nil,
          endpoint:,
          region:,
          target_model: nil,
          target_variant: nil,
          quantizer: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          dimensions: nil
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecAWSConfig.new(
              model: nil,
              endpoint: endpoint,
              region: region,
              targetModel: target_model,
              targetVariant: target_variant,
              service: "sagemaker",
              vectorizeClassName: vectorize_collection_name,
              dimensions: dimensions
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-aws` module.
        #
        # Note: `multi2vec_aws` is deprecated and will be removed after Q3 '26. Use a service-specific method instead, such as `multi2vec_aws_bedrock`.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimensions: The number of dimensions to use. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     region: The AWS region to run the model from. Defaults to `None`, which uses the server-defined defau
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_aws(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          region: nil,
          vector_index_config: nil
        )
          ::Weaviate::Warnings.emit(
            "`multi2vec_aws` is deprecated and will be removed after Q3 '26. Use a service-specific method instead, such as `multi2vec_aws_bedrock`."
          )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecAWSConfig.new(
              region: region,
              model: model,
              dimensions: dimensions,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-aws` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimensions: The number of dimensions to use. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     region: The AWS region to run the model from. Defaults to `None`, which uses the server-defined defau
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_aws_bedrock(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          region: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecAWSConfig.new(
              region: region,
              model: model,
              dimensions: dimensions,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `img2vec-neural` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/img2vec-neural)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     image_fields: The image fields to use. This is a required field and must match the property fields of the collection that are defined as `DataType.BLOB`.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.img2vec_neural(name: nil, quantizer: nil, image_fields:, vector_index_config: nil)
          VectorConfigCreate.new(
            name: name,
            vectorizer: Img2VecNeuralConfig.new(imageFields: image_fields),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-clip` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     inference_url: The inference url to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_clip(
          name: nil,
          quantizer: nil,
          inference_url: nil,
          image_fields: nil,
          text_fields: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecClipConfig.new(
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              inferenceUrl: inference_url
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-google` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimensions: The number of dimensions to use. Defaults to `None`, which uses the server-defined default.
        #     audio_fields: The audio fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     location: Where the model runs. REQUIRED.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     project_id: The project ID to use, REQUIRED.
        #     text_fields: The text fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     video_interval_seconds: Length of a video interval. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_google(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          audio_fields: nil,
          image_fields: nil,
          location:,
          model: nil,
          project_id:,
          text_fields: nil,
          video_fields: nil,
          video_interval_seconds: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecGoogleConfig.new(
              projectId: project_id,
              location: location,
              audioFields: Vectorizer.map_multi2vec_fields(audio_fields),
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              videoFields: Vectorizer.map_multi2vec_fields(video_fields),
              dimensions: dimensions,
              modelId: model,
              videoIntervalSeconds: video_interval_seconds
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-google` module with the Google Gemini API endpoint.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimensions: The number of dimensions to use. Defaults to `None`, which uses the server-defined default.
        #     audio_fields: The audio fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     video_interval_seconds: Length of a video interval. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_google_gemini(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          audio_fields: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          video_fields: nil,
          video_interval_seconds: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecGoogleConfig.new(
              projectId: nil,
              location: nil,
              apiEndpoint: "generativelanguage.googleapis.com",
              audioFields: Vectorizer.map_multi2vec_fields(audio_fields),
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              videoFields: Vectorizer.map_multi2vec_fields(video_fields),
              dimensions: dimensions,
              modelId: model,
              videoIntervalSeconds: video_interval_seconds
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-bind` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/imagebind/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     audio_fields: The audio fields to use in vectorization.
        #     depth_fields: The depth fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     imu_fields: The IMU fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     thermal_fields: The thermal fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_bind(
          name: nil,
          quantizer: nil,
          audio_fields: nil,
          depth_fields: nil,
          image_fields: nil,
          imu_fields: nil,
          text_fields: nil,
          thermal_fields: nil,
          video_fields: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecBindConfig.new(
              audioFields: Vectorizer.map_multi2vec_fields(audio_fields),
              depthFields: Vectorizer.map_multi2vec_fields(depth_fields),
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              IMUFields: Vectorizer.map_multi2vec_fields(imu_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              thermalFields: Vectorizer.map_multi2vec_fields(thermal_fields),
              videoFields: Vectorizer.map_multi2vec_fields(video_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-voyageai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     dimensions: The number of dimensions for the output embeddings. Defaults to `None`, which uses the model's default.
        #     truncation: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_voyageai(
          name: nil,
          quantizer: nil,
          base_url: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          video_fields: nil,
          dimensions: nil,
          truncation: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecVoyageaiConfig.new(
              baseURL: base_url,
              model: model,
              truncation: truncation,
              dimensions: dimensions,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              videoFields: Vectorizer.map_multi2vec_fields(video_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-nvidia` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     truncation: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_nvidia(
          name: nil,
          quantizer: nil,
          base_url: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          truncation: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecNvidiaConfig.new(
              baseURL: base_url,
              model: model,
              truncation: truncation,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-twelvelabs` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/twelvelabs/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_twelvelabs(
          name: nil,
          quantizer: nil,
          base_url: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecTwelvelabsConfig.new(
              baseURL: base_url,
              model: model,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `ref2vec-centroid` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/text2vec-gpt4all)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     method: The method to use. Defaults to `mean`.
        #     reference_properties: The reference properties to use in vectorization, REQUIRED.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.ref2vec_centroid(
          name: nil,
          quantizer: nil,
          method: "mean",
          reference_properties:,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Ref2VecCentroidConfig.new(referenceProperties: reference_properties, method: method),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-openai` module running with Azure.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai-azure/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     deployment_id: The deployment ID to use, REQUIRED.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     resource_name: The resource name to use, REQUIRED.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_azure_openai(
          name: nil,
          quantizer: nil,
          base_url: nil,
          deployment_id:,
          dimensions: nil,
          model: nil,
          resource_name:,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecAzureOpenAIConfig.new(
              baseURL: base_url,
              dimensions: dimensions,
              model: model,
              resourceName: resource_name,
              deploymentId: deployment_id,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-gpt4all` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/gpt4all/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_gpt4all(
          name: nil,
          quantizer: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          ::Weaviate::Warnings.emit(
            "The `text2vec-gpt4all` vectorizer is deprecated and will be removed after Q3 '26. See the docs (https://docs.weaviate.io/weaviate/model-providers) for alternatives."
          )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGPT4AllConfig.new(vectorizeClassName: vectorize_collection_name),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-huggingface` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/huggingface/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     endpoint_url: The endpoint URL to use. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     passage_model: The passage model to use. Defaults to `None`, which uses the server-defined default.
        #     query_model: The query model to use. Defaults to `None`, which uses the server-defined default.
        #     wait_for_model: Whether to wait for the model to be loaded. Defaults to `None`, which uses the server-defined default.
        #     use_gpu: Whether to use the GPU. Defaults to `None`, which uses the server-defined default.
        #     use_cache: Whether to use the cache. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_huggingface(
          name: nil,
          quantizer: nil,
          endpoint_url: nil,
          model: nil,
          passage_model: nil,
          query_model: nil,
          wait_for_model: nil,
          use_gpu: nil,
          use_cache: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecHuggingFaceConfig.new(
              model: model,
              passageModel: passage_model,
              queryModel: query_model,
              endpointURL: endpoint_url,
              waitForModel: wait_for_model,
              useGPU: use_gpu,
              useCache: use_cache,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     api_endpoint: The API endpoint to use without a leading scheme such as `http://`. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     project_id: The project ID to use, REQUIRED.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     task_type: The task type to use (e.g. `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`). Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     location: The Google Vertex AI region to run the model in. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_google(
          name: nil,
          quantizer: nil,
          api_endpoint: nil,
          dimensions: nil,
          model: nil,
          project_id:,
          title_property: nil,
          task_type: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          location: nil
        )
          ::Weaviate::Warnings.emit(
            "`text2vec_google` is deprecated and will be removed after Q3 '26. Use a service-specific method instead, such as `text2vec_google_vertex` or `text2vec_google_gemini`."
          )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: project_id,
              apiEndpoint: api_endpoint,
              dimensions: dimensions,
              modelId: model,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: task_type,
              location: location
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimenions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     task_type: The task type to use (e.g. `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`). Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_google_aistudio(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          model: nil,
          title_property: nil,
          task_type: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          ::Weaviate::Warnings.emit(
            "`text2vec_google_aistudio` is deprecated and will be removed after Q3 '26. Use `text2vec_google_gemini` instead."
          )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: nil,
              apiEndpoint: "generativelanguage.googleapis.com",
              dimensions: dimensions,
              modelId: model,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: task_type,
              location: nil
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     dimenions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     task_type: The task type to use (e.g. `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`). Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_google_gemini(
          name: nil,
          quantizer: nil,
          dimensions: nil,
          model: nil,
          title_property: nil,
          task_type: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: nil,
              apiEndpoint: "generativelanguage.googleapis.com",
              dimensions: dimensions,
              modelId: model,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: task_type,
              location: nil
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     api_endpoint: The API endpoint to use without a leading scheme such as `http://`. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     project_id: The project ID to use, REQUIRED.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     task_type: The task type to use (e.g. `RETRIEVAL_QUERY`, `RETRIEVAL_DOCUMENT`). Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     location: The Google Vertex AI region to run the model in. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_google_vertex(
          name: nil,
          quantizer: nil,
          api_endpoint: nil,
          dimensions: nil,
          model: nil,
          project_id:,
          title_property: nil,
          task_type: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          location: nil
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: project_id,
              apiEndpoint: api_endpoint,
              dimensions: dimensions,
              modelId: model,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: task_type,
              location: location
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-transformers` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     inference_url: The inferenceUrl to use where API requests should go. You can use either this OR passage/query_inference_url. Defaults to `None`, which uses the server-defined default.
        #     passage_inference_url: The inferenceUrl to use where passage API requests should go. You can use either this and query_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        #     pooling_strategy: The pooling strategy to use. Defaults to `masked_mean`.
        #     query_inference_url: The inferenceUrl to use where query API requests should go. You can use either this and passage_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_transformers(
          name: nil,
          dimensions: nil,
          quantizer: nil,
          inference_url: nil,
          passage_inference_url: nil,
          pooling_strategy: "masked_mean",
          query_inference_url: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecTransformersConfig.new(
              poolingStrategy: pooling_strategy,
              dimensions: dimensions,
              vectorizeClassName: vectorize_collection_name,
              inferenceUrl: inference_url,
              passageInferenceUrl: passage_inference_url,
              queryInferenceUrl: query_inference_url
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-jinaai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings) for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to send the vectorization requests to. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_jinaai(
          name: nil,
          quantizer: nil,
          base_url: nil,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecJinaConfig.new(
              baseURL: base_url,
              dimensions: dimensions,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `multi2vec-jinaai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings (only available for some models). Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     text_fields: The text fields to use in vectorization.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        def self.multi2vec_jinaai(
          name: nil,
          quantizer: nil,
          base_url: nil,
          dimensions: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          vector_index_config: nil
        )
          VectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecJinaConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: dimensions,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-voyageai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings#available-models) for more details.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_voyageai(
          name: nil,
          base_url: nil,
          dimensions: nil,
          model: nil,
          quantizer: nil,
          source_properties: nil,
          truncate: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecVoyageConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              truncate: truncate,
              dimensions: dimensions
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        def self.text2vec_weaviate(
          name: nil,
          quantizer: nil,
          base_url: nil,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecWeaviateConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              dimensions: dimensions
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end

        # Create a vector using the `text2vec-nvidia` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the vector.
        #     quantizer: The quantizer to use for the vector index. If not provided, no quantization will be applied.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Configure.VectorIndex` to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings#available-models) for more details.
        #
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_nvidia(
          name: nil,
          quantizer: nil,
          base_url: nil,
          model: nil,
          truncate: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          VectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecNvidiaConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              truncate: truncate
            ),
            vector_index_config: IndexWrappers.single(vector_index_config, quantizer)
          )
        end
      end


      # Port of _VectorsUpdate (exposed as `Reconfigure::Vectors`).
      module VectorsUpdate
        # Update the vector index configuration of a vector.
        #
        # This is the only update operation allowed currently. If you wish to change the vectorization configuration itself, you will have to
        # recreate the collection with the new configuration.
        #
        # Args:
        #     name: The name of the vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Reconfigure.VectorIndex` to create a vector index configuration. `None` by default
        def self.update(name: nil, vector_index_config:)
          VectorConfigUpdate.new(name: name || "default", vector_index_config: vector_index_config)
        end
      end
    end
  end
end
