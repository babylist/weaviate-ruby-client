# frozen_string_literal: true

require_relative "base"
require_relative "vectorizers"

# Port of weaviate.collections.classes.config_named_vectors.
module Weaviate
  module Classes
    module Config
      # Shared behaviour of NamedVectorConfigCreate / VectorConfigCreate: the pydantic
      # aliases `source_properties` → properties and `vector_index_config` → vectorIndexConfig.
      module VectorConfigCreateBehaviour
        def initialize(source_properties: nil, vector_index_config: nil, **kwargs)
          kwargs[:properties] = source_properties unless kwargs.key?(:properties)
          kwargs[:vectorIndexConfig] = vector_index_config unless kwargs.key?(:vectorIndexConfig)
          super(**kwargs)
        end

        def after_initialize
          if !properties.nil? && (!properties.is_a?(Array) || properties.empty? || !properties.all?(String))
            raise ::Weaviate::Classes::Config::ValidationError,
                  "#{self.class.name}: source_properties must be a non-empty list of strings, got #{properties.inspect}"
          end
          return if vectorizer.is_a?(VectorizerConfigCreate)

          raise ::Weaviate::Classes::Config::ValidationError,
                "#{self.class.name}: vectorizer must be a VectorizerConfigCreate, got #{vectorizer.inspect}"
        end

        def to_dict(emit_default_vector_index_type: true)
          ret = parse_vectorizer
          if !vectorIndexConfig.nil?
            ret["vectorIndexType"] = VectorConfigCreateBehaviour.index_type_of(vectorIndexConfig).to_s
            ret["vectorIndexConfig"] = vectorIndexConfig.to_dict
          elsif emit_default_vector_index_type
            ret["vectorIndexType"] = vectorIndexType.to_s
          end
          ret
        end

        def self.index_type_of(config)
          config.respond_to?(:vector_index_type) ? config.vector_index_type : config.class.vector_index_type
        end

        private

        def parse_vectorizer
          options = vectorizer.to_dict
          options["properties"] = properties unless properties.nil?
          { "vectorizer" => { vectorizer.vectorizer.to_s => options } }
        end
      end

      # Shared behaviour of NamedVectorConfigUpdate / VectorConfigUpdate (alias `vector_index_config`).
      module VectorConfigUpdateBehaviour
        def initialize(vector_index_config: nil, **kwargs)
          kwargs[:vectorIndexConfig] = vector_index_config unless kwargs.key?(:vectorIndexConfig)
          super(**kwargs)
        end

        def after_initialize
          raise ::Weaviate::Classes::Config::ValidationError,
                "#{self.class.name}: name must be a String, got #{name.inspect}" unless name.is_a?(String)
          return unless vectorIndexConfig.nil?

          raise ::Weaviate::Classes::Config::ValidationError, "#{self.class.name}: vector_index_config is required"
        end
      end

      # Port of _NamedVectorConfigCreate.
      class NamedVectorConfigCreate < ConfigCreateModel
        include VectorConfigCreateBehaviour

        attribute :name
        attribute :properties, default: nil
        attribute :vectorizer
        attribute :vectorIndexType, default: -> { ::Weaviate::Classes::Config::VectorIndexType::HNSW }
        attribute :vectorIndexConfig, default: nil

        def after_initialize
          super
          raise ::Weaviate::Classes::Config::ValidationError,
                "#{self.class.name}: name must be a String, got #{name.inspect}" unless name.is_a?(String)
        end
      end

      # Port of _NamedVectorConfigUpdate.
      class NamedVectorConfigUpdate < ConfigUpdateModel
        include VectorConfigUpdateBehaviour

        attribute :name
        attribute :vectorIndexConfig
      end

      # Port of _NamedVectors (exposed as `Configure::NamedVectors`).
      module NamedVectors
        # Create a named vector using no vectorizer. You will need to provide the vectors yourself.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        def self.none(name, vector_index_config: nil)
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: VectorizerConfigCreate.new(vectorizer: Vectorizers::NONE),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using no vectorizer. You will need to provide the vectors yourself.
        #
        # Args:
        #     name: The name of the named vector.
        #     module_name: The name of the custom module to use.
        #     module_config: The configuration of the custom module to use.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        def self.custom(name, module_name:, module_config: nil, source_properties: nil, vector_index_config: nil)
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: VectorizerCustomConfig.new(
              vectorizer: EnumLikeStr.new(string: module_name),
              module_config: module_config
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2colbert_jinaai` module.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/colbert)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of dimensions. Applicable to v3 OpenAI models only. Defaults to `None`, which uses the server-defined default.
        def self.text2colbert_jinaai(
          name,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vector_index_config: vector_index_config,
            vectorizer: Text2ColbertJinaAIConfig.new(
              model: model,
              dimensions: dimensions,
              vectorizeClassName: vectorize_collection_name
            )
          )
        end

        # Create a named vector using the `text2vec_cohere` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_cohere(
          name,
          base_url: nil,
          model: nil,
          truncate: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecCohereConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: nil,
              truncate: truncate,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_cohere` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_cohere(
          name,
          base_url: nil,
          image_fields: nil,
          model: nil,
          text_fields: nil,
          truncate: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecCohereConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: nil,
              truncate: truncate,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_contextionary` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/text2vec-contextionary)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_contextionary(
          name,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecContextionaryConfig.new(vectorizeClassName: vectorize_collection_name),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-databricks` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/databricks/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     endpoint: The endpoint to use.
        #     instruction: The instruction strategy to use. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_databricks(
          name,
          endpoint:,
          instruction: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecDatabricksConfig.new(
              endpoint: endpoint,
              instruction: instruction,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-mistral` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/mistral/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_mistral(
          name,
          base_url: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecMistralConfig.new(
              baseURL: base_url,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-ollama` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/ollama/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     api_endpoint: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #         Docker users may need to specify an alias, such as `http://host.docker.internal:11434` so that the container can access the host machine.
        def self.text2vec_ollama(
          name,
          api_endpoint: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecOllamaConfig.new(
              apiEndpoint: api_endpoint,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_openai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     model_version: The model version to use. Defaults to `None`, which uses the server-defined default.
        #     type_: The type of model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of dimensions. Applicable to v3 OpenAI models only. Defaults to `None`, which uses the server-defined default.
        #     endpoint: The API path to append to `base_url`, e.g. `/api/v3/embeddings`. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_openai(
          name,
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
          NamedVectorConfigCreate.new(
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
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_aws` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     region: The AWS region to run the model from, REQUIRED.
        #     endpoint: The endpoint to use. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use.
        #     service: The AWS service to use. Defaults to `bedrock`.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_aws(
          name,
          region:,
          endpoint: nil,
          model: nil,
          service: "bedrock",
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          dimensions: nil
        )
          NamedVectorConfigCreate.new(
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
            vector_index_config: vector_index_config
          )
        end

        # Create a `Img2VecNeuralConfig` object for use when vectorizing using the `img2vec-neural` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/img2vec-neural)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     image_fields: The image fields to use. This is a required field and must match the property fields of the collection that are defined as `DataType.BLOB`.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        def self.img2vec_neural(name, image_fields:, vector_index_config: nil)
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Img2VecNeuralConfig.new(imageFields: image_fields),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_clip` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     inference_url: The inference url to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        def self.multi2vec_clip(
          name,
          inference_url: nil,
          image_fields: nil,
          text_fields: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecClipConfig.new(
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              inferenceUrl: inference_url
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_google` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     location: Where the model runs. REQUIRED.
        #     project_id: The project ID to use, REQUIRED.
        #     audio_fields: The audio fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     dimensions: The number of dimensions to use. Defaults to `None`, which uses the server-defined default.
        #     video_interval_seconds: Length of a video interval. Defaults to `None`, which uses the server-defined default.
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        def self.multi2vec_google(
          name,
          location:,
          project_id:,
          audio_fields: nil,
          image_fields: nil,
          text_fields: nil,
          video_fields: nil,
          dimensions: nil,
          video_interval_seconds: nil,
          model_id: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecGoogleConfig.new(
              projectId: project_id,
              location: location,
              audioFields: Vectorizer.map_multi2vec_fields(audio_fields),
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              videoFields: Vectorizer.map_multi2vec_fields(video_fields),
              dimensions: dimensions,
              modelId: model_id,
              videoIntervalSeconds: video_interval_seconds
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_bind` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/imagebind/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     audio_fields: The audio fields to use in vectorization.
        #     depth_fields: The depth fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     imu_fields: The IMU fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     thermal_fields: The thermal fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.multi2vec_bind(
          name,
          audio_fields: nil,
          depth_fields: nil,
          image_fields: nil,
          imu_fields: nil,
          text_fields: nil,
          thermal_fields: nil,
          video_fields: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
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
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_voyageai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncation: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_voyageai(
          name,
          base_url: nil,
          model: nil,
          truncation: nil,
          output_encoding: nil,
          image_fields: nil,
          text_fields: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecVoyageaiConfig.new(
              baseURL: base_url,
              model: model,
              truncation: truncation,
              dimensions: nil,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields),
              videoFields: nil
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_nvidia` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncation: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_nvidia(
          name,
          base_url: nil,
          model: nil,
          truncation: nil,
          output_encoding: nil,
          image_fields: nil,
          text_fields: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecNvidiaConfig.new(
              baseURL: base_url,
              model: model,
              truncation: truncation,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `ref2vec_centroid` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/text2vec-gpt4all)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     reference_properties: The reference properties to use in vectorization, REQUIRED.
        #     method: The method to use. Defaults to `mean`.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        def self.ref2vec_centroid(name, reference_properties:, method: "mean", vector_index_config: nil)
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Ref2VecCentroidConfig.new(referenceProperties: reference_properties, method: method),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_azure_openai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai-azure/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     resource_name: The resource name to use, REQUIRED.
        #     deployment_id: The deployment ID to use, REQUIRED.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_azure_openai(
          name,
          resource_name:,
          deployment_id:,
          base_url: nil,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
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
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_gpt4all` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/gpt4all/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_gpt4all(
          name,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGPT4AllConfig.new(vectorizeClassName: vectorize_collection_name),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_huggingface` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/huggingface/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     passage_model: The passage model to use. Defaults to `None`, which uses the server-defined default.
        #     query_model: The query model to use. Defaults to `None`, which uses the server-defined default.
        #     endpoint_url: The endpoint URL to use. Defaults to `None`, which uses the server-defined default.
        #     wait_for_model: Whether to wait for the model to be loaded. Defaults to `None`, which uses the server-defined default.
        #     use_gpu: Whether to use the GPU. Defaults to `None`, which uses the server-defined default.
        #     use_cache: Whether to use the cache. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_huggingface(
          name,
          model: nil,
          passage_model: nil,
          query_model: nil,
          endpoint_url: nil,
          wait_for_model: nil,
          use_gpu: nil,
          use_cache: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
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
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     project_id: The project ID to use, REQUIRED.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     api_endpoint: The API endpoint to use without a leading scheme such as `http://`. Defaults to `None`, which uses the server-defined default
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     location: The Google Vertex AI region to run the model in. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_google(
          name,
          project_id:,
          api_endpoint: nil,
          model_id: nil,
          title_property: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          location: nil
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: project_id,
              apiEndpoint: api_endpoint,
              dimensions: nil,
              modelId: model_id,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: nil,
              location: location
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_google` model.
        #
        # See the [documentation]https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        def self.text2vec_google_aistudio(
          name,
          model_id: nil,
          title_property: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecGoogleConfig.new(
              projectId: nil,
              apiEndpoint: "generativelanguage.googleapis.com",
              dimensions: nil,
              modelId: model_id,
              vectorizeClassName: vectorize_collection_name,
              titleProperty: title_property,
              taskType: nil,
              location: nil
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec_transformers` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     pooling_strategy: The pooling strategy to use. Defaults to `masked_mean`.
        #     inference_url: The inferenceUrl to use where API requests should go. You can use either this OR passage/query_inference_url. Defaults to `None`, which uses the server-defined default.
        #     passage_inference_url: The inferenceUrl to use where passage API requests should go. You can use either this and query_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        #     query_inference_url: The inferenceUrl to use where query API requests should go. You can use either this and passage_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_transformers(
          name,
          dimensions: nil,
          pooling_strategy: "masked_mean",
          inference_url: nil,
          passage_inference_url: nil,
          query_inference_url: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecTransformersConfig.new(
              dimensions: dimensions,
              poolingStrategy: pooling_strategy,
              vectorizeClassName: vectorize_collection_name,
              inferenceUrl: inference_url,
              passageInferenceUrl: passage_inference_url,
              queryInferenceUrl: query_inference_url
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-jinaai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings) for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to send the vectorization requests to. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_jinaai(
          name,
          base_url: nil,
          dimensions: nil,
          model: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecJinaConfig.new(
              baseURL: base_url,
              dimensions: dimensions,
              model: model,
              vectorizeClassName: vectorize_collection_name
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `multi2vec_jinaai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings (only available for some models). Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_jinaai(
          name,
          base_url: nil,
          model: nil,
          dimensions: nil,
          image_fields: nil,
          text_fields: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            vectorizer: Multi2VecJinaConfig.new(
              baseURL: base_url,
              model: model,
              dimensions: dimensions,
              imageFields: Vectorizer.map_multi2vec_fields(image_fields),
              textFields: Vectorizer.map_multi2vec_fields(text_fields)
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-jinaai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings#available-models) for more details.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_voyageai(
          name,
          model: nil,
          base_url: nil,
          truncate: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecVoyageConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              truncate: truncate,
              dimensions: nil
            ),
            vector_index_config: vector_index_config
          )
        end

        def self.text2vec_weaviate(
          name,
          model: nil,
          base_url: nil,
          dimensions: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecWeaviateConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              dimensions: dimensions
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-nvidia` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings#available-models) for more details.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_nvidia(
          name,
          model: nil,
          base_url: nil,
          truncate: nil,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecNvidiaConfig.new(
              model: model,
              vectorizeClassName: vectorize_collection_name,
              baseURL: base_url,
              truncate: truncate
            ),
            vector_index_config: vector_index_config
          )
        end

        # Create a named vector using the `text2vec-model2vec` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/model2vec/embeddings)
        # for detailed usage.
        #
        # Args:
        #     name: The name of the named vector.
        #     source_properties: Which properties should be included when vectorizing. By default all text properties are included.
        #     vector_index_config: The configuration for Weaviate's vector index. Use wvc.config.Configure.VectorIndex to create a vector index configuration. None by default
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     inference_url: The inference url to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_model2vec(
          name,
          source_properties: nil,
          vector_index_config: nil,
          vectorize_collection_name: true,
          inference_url: nil
        )
          NamedVectorConfigCreate.new(
            name: name,
            source_properties: source_properties,
            vectorizer: Text2VecModel2VecConfig.new(
              vectorizeClassName: vectorize_collection_name,
              inferenceUrl: inference_url
            ),
            vector_index_config: vector_index_config
          )
        end
      end


      # Port of _NamedVectorsUpdate (exposed as `Reconfigure::NamedVectors`).
      module NamedVectorsUpdate
        # Update the vector index configuration of a named vector.
        #
        # This is the only update operation allowed currently. If you wish to change the vectorization configuration itself, you will have to
        # recreate the collection with the new configuration.
        #
        # Args:
        #     name: The name of the named vector.
        #     vector_index_config: The configuration for Weaviate's vector index. Use `wvc.config.Reconfigure.VectorIndex` to create a vector index configuration. `None` by default
        def self.update(name, vector_index_config:)
          NamedVectorConfigUpdate.new(name: name, vector_index_config: vector_index_config)
        end
      end
    end
  end
end
