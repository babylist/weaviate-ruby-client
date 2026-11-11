# frozen_string_literal: true

require_relative "vectorizers"

module Weaviate
  module Classes
    module Config
      # Port of _Vectorizer (exposed as `Configure::Vectorizer`).
      #
      # Use this factory to create the correct object for the `vectorizer_config` argument in the
      # `collections.create()` method. Each method provides options specific to the named vectorizer.
      module Vectorizer
        # Port of _map_multi2vec_fields: Strings become Multi2VecField instances.
        def self.map_multi2vec_fields(fields)
          return nil if fields.nil?

          fields.map { |f| f.is_a?(String) ? Multi2VecField.new(name: f) : f }
        end

        # Create a `_VectorizerConfigCreate` object with the vectorizer set to `Vectorizer.NONE`.
        def self.none
          VectorizerConfigCreate.new(vectorizer: Vectorizers::NONE)
        end

        # Create a `_Img2VecNeuralConfigCreate` object for use when vectorizing using the `img2vec-neural` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/img2vec-neural)
        # for detailed usage.
        #
        # Args:
        #     image_fields: The image fields to use. This is a required field and must match the property fields
        #         of the collection that are defined as `DataType.BLOB`.
        def self.img2vec_neural(image_fields)
          Img2VecNeuralConfig.new(imageFields: image_fields)
        end

        # Create a `_Multi2VecClipConfigCreate` object for use when vectorizing using the `multi2vec-clip` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     inference_url: The inference url to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Deprecated, has no effect.
        def self.multi2vec_clip(
          image_fields: nil,
          text_fields: nil,
          interference_url: nil,
          inference_url: nil,
          vectorize_collection_name: true
        )
          unless interference_url.nil?
            unless inference_url.nil?
              raise ArgumentError,
                    "You have provided `interference_url` as well as `inference_url`. Please only provide " \
                    "`inference_url`, as `interference_url` is deprecated."
            end

            ::Weaviate::Warnings.emit(
              "This parameter is deprecated and will be removed in a future release. Please use `inference_url` instead."
            )
          end

          Multi2VecClipConfig.new(
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields),
            inferenceUrl: inference_url
          )
        end

        # Create a `_Multi2VecBindConfigCreate` object for use when vectorizing using the `multi2vec-clip` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/imagebind/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     audio_fields: The audio fields to use in vectorization.
        #     depth_fields: The depth fields to use in vectorization.
        #     image_fields: The image fields to use in vectorization.
        #     imu_fields: The IMU fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     thermal_fields: The thermal fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     vectorize_collection_name: Deprecated, has no effect.
        def self.multi2vec_bind(
          audio_fields: nil,
          depth_fields: nil,
          image_fields: nil,
          imu_fields: nil,
          text_fields: nil,
          thermal_fields: nil,
          video_fields: nil,
          vectorize_collection_name: true
        )
          Multi2VecBindConfig.new(
            audioFields: Vectorizer.map_multi2vec_fields(audio_fields),
            depthFields: Vectorizer.map_multi2vec_fields(depth_fields),
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            IMUFields: Vectorizer.map_multi2vec_fields(imu_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields),
            thermalFields: Vectorizer.map_multi2vec_fields(thermal_fields),
            videoFields: Vectorizer.map_multi2vec_fields(video_fields)
          )
        end

        # Create a `_Ref2VecCentroidConfigCreate` object for use when vectorizing using the `ref2vec-centroid` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/ref2vec-centroid)
        # for detailed usage.
        #
        # Args:
        #     reference_properties: The reference properties to use in vectorization, REQUIRED.
        #     method: The method to use in vectorization. Defaults to `mean`.
        def self.ref2vec_centroid(reference_properties, method: "mean")
          Ref2VecCentroidConfig.new(referenceProperties: reference_properties, method: method)
        end

        # Create a `_Text2VecAWSConfigCreate` object for use when vectorizing using the `text2vec-aws` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/aws/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use, REQUIRED for service "bedrock".
        #     region: The AWS region to run the model from, REQUIRED.
        #     endpoint: The model to use, REQUIRED for service "sagemaker".
        #     service: The AWS service to use, options are "bedrock" and "sagemaker".
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_aws(
          model: nil,
          region: "",
          endpoint: nil,
          service: "bedrock",
          vectorize_collection_name: true,
          dimensions: nil
        )
          Text2VecAWSConfig.new(
            model: model,
            region: region,
            vectorizeClassName: vectorize_collection_name,
            service: service,
            endpoint: endpoint,
            targetModel: nil,
            targetVariant: nil,
            dimensions: dimensions
          )
        end

        # Create a `_Text2VecAzureOpenAIConfigCreate` object for use when vectorizing using the `text2vec-azure-openai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai-azure/embeddings)
        # for detailed usage.
        #
        # Args:
        #     resource_name: The resource name to use, REQUIRED.
        #     deployment_id: The deployment ID to use, REQUIRED.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_azure_openai(
          resource_name,
          deployment_id:,
          vectorize_collection_name: true,
          base_url: nil,
          dimensions: nil,
          model: nil
        )
          Text2VecAzureOpenAIConfig.new(
            baseURL: base_url,
            dimensions: dimensions,
            resourceName: resource_name,
            deploymentId: deployment_id,
            vectorizeClassName: vectorize_collection_name,
            model: model
          )
        end

        # Create a `_Text2VecContextionaryConfigCreate` object for use when vectorizing using the `text2vec-contextionary` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/modules/retriever-vectorizer-modules/text2vec-contextionary)
        # for detailed usage.
        #
        # Args:
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_contextionary(vectorize_collection_name: true)
          Text2VecContextionaryConfig.new(vectorizeClassName: vectorize_collection_name)
        end

        # Create a `_VectorizerCustomConfig` object for use when vectorizing using a custom specification.
        #
        # Args:
        #     module_name: The name of the module to use, REQUIRED.
        #     module_config: The configuration to use for the module. Defaults to `None`, which uses the server-defined default.
        def self.custom(module_name, module_config: nil)
          VectorizerCustomConfig.new(vectorizer: EnumLikeStr.new(string: module_name), module_config: module_config)
        end

        # Create a `_Text2VecCohereConfigCreate` object for use when vectorizing using the `text2vec-cohere` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_cohere(model: nil, truncate: nil, vectorize_collection_name: true, base_url: nil)
          Text2VecCohereConfig.new(
            baseURL: base_url,
            model: model,
            dimensions: nil,
            truncate: truncate,
            vectorizeClassName: vectorize_collection_name
          )
        end

        # Create a `_Multi2VecCohereConfig` object for use when vectorizing using the `multi2vec-cohere` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/cohere/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Deprecated, has no effect.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_cohere(
          model: nil,
          truncate: nil,
          vectorize_collection_name: true,
          base_url: nil,
          image_fields: nil,
          text_fields: nil
        )
          Multi2VecCohereConfig.new(
            baseURL: base_url,
            model: model,
            dimensions: nil,
            truncate: truncate,
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields)
          )
        end

        # Create a `_Multi2VecVoyageaiConfig` object for use when vectorizing using the `multi2vec-voyageai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncation: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     output_encoding: Deprecated, has no effect.
        #     vectorize_collection_name: Deprecated, has no effect.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_voyageai(
          model: nil,
          truncation: nil,
          output_encoding:,
          vectorize_collection_name: true,
          base_url: nil,
          image_fields: nil,
          text_fields: nil
        )
          Multi2VecVoyageaiConfig.new(
            baseURL: base_url,
            model: model,
            truncation: truncation,
            dimensions: nil,
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields),
            videoFields: nil
          )
        end

        # Create a `_Multi2VecNvidiaConfig` object for use when vectorizing using the `multi2vec-nvidia` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     truncate: The truncation strategy to use. Defaults to `None`, which uses the server-defined default.
        #     output_encoding: Deprecated, has no effect.
        #     vectorize_collection_name: Deprecated, has no effect.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_nvidia(
          model: nil,
          truncation: nil,
          output_encoding: nil,
          vectorize_collection_name: true,
          base_url: nil,
          image_fields: nil,
          text_fields: nil
        )
          Multi2VecNvidiaConfig.new(
            baseURL: base_url,
            model: model,
            truncation: truncation,
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields)
          )
        end

        # Create a `_Text2VecDatabricksConfig` object for use when vectorizing using the `text2vec-databricks` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/databricks/embeddings)
        # for detailed usage.
        #
        # Args:
        #     endpoint: The endpoint to use.
        #     instruction: The instruction strategy to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_databricks(endpoint:, instruction: nil, vectorize_collection_name: true)
          Text2VecDatabricksConfig.new(
            endpoint: endpoint,
            instruction: instruction,
            vectorizeClassName: vectorize_collection_name
          )
        end

        # Create a `_Text2VecGPT4AllConfigCreate` object for use when vectorizing using the `text2vec-gpt4all` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/gpt4all/embeddings)
        # for detailed usage.
        #
        # Args:
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_gpt4all(vectorize_collection_name: true)
          Text2VecGPT4AllConfig.new(vectorizeClassName: vectorize_collection_name)
        end

        # Create a `_Text2VecHuggingFaceConfigCreate` object for use when vectorizing using the `text2vec-huggingface` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/huggingface/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     passage_model: The passage model to use. Defaults to `None`, which uses the server-defined default.
        #     query_model: The query model to use. Defaults to `None`, which uses the server-defined default.
        #     endpoint_url: The endpoint URL to use. Defaults to `None`, which uses the server-defined default.
        #     wait_for_model: Whether to wait for the model to be loaded. Defaults to `None`, which uses the server-defined default.
        #     use_gpu: Whether to use the GPU. Defaults to `None`, which uses the server-defined default.
        #     use_cache: Whether to use the cache. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_huggingface(
          model: nil,
          passage_model: nil,
          query_model: nil,
          endpoint_url: nil,
          wait_for_model: nil,
          use_gpu: nil,
          use_cache: nil,
          vectorize_collection_name: true
        )
          Text2VecHuggingFaceConfig.new(
            model: model,
            passageModel: passage_model,
            queryModel: query_model,
            endpointURL: endpoint_url,
            waitForModel: wait_for_model,
            useGPU: use_gpu,
            useCache: use_cache,
            vectorizeClassName: vectorize_collection_name
          )
        end

        # Create a `_Text2VecMistralConfig` object for use when vectorizing using the `text2vec-mistral` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/mistral/embeddings)
        # for detailed usage.
        #
        # Args:
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_mistral(base_url: nil, model: nil, vectorize_collection_name: true)
          Text2VecMistralConfig.new(baseURL: base_url, model: model, vectorizeClassName: vectorize_collection_name)
        end

        # Create a `_Text2VecOllamaConfig` object for use when vectorizing using the `text2vec-ollama` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/ollama/embeddings)
        # for detailed usage.
        #
        # Args:
        #     api_endpoint: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #         Docker users may need to specify an alias, such as `http://host.docker.internal:11434` so that the container can access the host machine.
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_ollama(api_endpoint: nil, model: nil, vectorize_collection_name: true)
          Text2VecOllamaConfig.new(
            apiEndpoint: api_endpoint,
            model: model,
            vectorizeClassName: vectorize_collection_name
          )
        end

        # Create a `_Text2VecOpenAIConfigCreate` object for use when vectorizing using the `text2vec-openai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/openai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     model_version: The model version to use. Defaults to `None`, which uses the server-defined default.
        #     type_: The type of model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: Number of dimensions. Applicable to v3 OpenAI models only. Defaults to `None`, which uses the server-defined default.
        #     endpoint: The API path to append to `base_url`, e.g. `/api/v3/embeddings`. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_openai(
          model: nil,
          model_version: nil,
          type_: nil,
          vectorize_collection_name: true,
          base_url: nil,
          dimensions: nil,
          endpoint: nil
        )
          Text2VecOpenAIConfig.new(
            baseURL: base_url,
            model: model,
            modelVersion: model_version,
            type_: type_,
            vectorizeClassName: vectorize_collection_name,
            dimensions: dimensions,
            endpoint: endpoint
          )
        end

        # Create a `_Text2VecGoogleConfig` object for use when vectorizing using the `text2vec-google` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_google_aistudio(model_id: nil, title_property: nil, vectorize_collection_name: true)
          Text2VecGoogleConfig.new(
            projectId: nil,
            apiEndpoint: "generativelanguage.googleapis.com",
            dimensions: nil,
            modelId: model_id,
            vectorizeClassName: vectorize_collection_name,
            titleProperty: title_property,
            taskType: nil,
            location: nil
          )
        end

        # Create a `_Text2VecGoogleConfig` object for use when vectorizing using the `text2vec-google` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings)
        # for detailed usage.
        #
        # Args:
        #     project_id: The project ID to use, REQUIRED.
        #     api_endpoint: The API endpoint to use without a leading scheme such as `http://`. Defaults to `None`, which uses the server-defined default
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        #     title_property: The Weaviate property name for the `gecko-002` or `gecko-003` model to use as the title.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     dimensions: The dimensionality of the vectors. Defaults to `None`, which uses the server-defined default.
        #     location: The Google Vertex AI region to run the model in. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_google(
          project_id,
          api_endpoint: nil,
          model_id: nil,
          title_property: nil,
          vectorize_collection_name: true,
          location: nil
        )
          Text2VecGoogleConfig.new(
            projectId: project_id,
            apiEndpoint: api_endpoint,
            dimensions: nil,
            modelId: model_id,
            vectorizeClassName: vectorize_collection_name,
            titleProperty: title_property,
            taskType: nil,
            location: location
          )
        end

        # Create a `_Multi2VecGoogleConfig` object for use when vectorizing using the `text2vec-google` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/google/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     location: Where the model runs. REQUIRED.
        #     project_id: The project ID to use, REQUIRED.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        #     video_fields: The video fields to use in vectorization.
        #     model_id: The model ID to use. Defaults to `None`, which uses the server-defined default.
        #     video_interval_seconds: Length of a video interval. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Deprecated, has no effect.
        def self.multi2vec_google(
          location:,
          project_id:,
          image_fields: nil,
          text_fields: nil,
          video_fields: nil,
          model_id: nil,
          video_interval_seconds: nil,
          vectorize_collection_name: true
        )
          Multi2VecGoogleConfig.new(
            projectId: project_id,
            location: location,
            audioFields: nil,
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields),
            videoFields: Vectorizer.map_multi2vec_fields(video_fields),
            dimensions: nil,
            modelId: model_id,
            videoIntervalSeconds: video_interval_seconds
          )
        end

        # Create a `_Text2VecTransformersConfigCreate` object for use when vectorizing using the `text2vec-transformers` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/transformers/embeddings)
        # for detailed usage.
        #
        # Args:
        #     pooling_strategy: The pooling strategy to use. Defaults to `masked_mean`.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     inference_url: The inference url to use where API requests should go. You can use either this OR passage/query_inference_url. Defaults to `None`, which uses the server-defined default.
        #     passage_inference_url: The inference url to use where passage API requests should go. You can use either this and query_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        #     query_inference_url: The inference url to use where query API requests should go. You can use either this and passage_inference_url OR inference_url. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_transformers(
          pooling_strategy: "masked_mean",
          dimensions: nil,
          vectorize_collection_name: true,
          inference_url: nil,
          passage_inference_url: nil,
          query_inference_url: nil
        )
          Text2VecTransformersConfig.new(
            poolingStrategy: pooling_strategy,
            dimensions: dimensions,
            vectorizeClassName: vectorize_collection_name,
            inferenceUrl: inference_url,
            passageInferenceUrl: passage_inference_url,
            queryInferenceUrl: query_inference_url
          )
        end

        # Create a `_Text2VecJinaConfigCreate` object for use when vectorizing using the `text2vec-jinaai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings#available-models) for more details.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     base_url: The base URL to send the vectorization requests to. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_jinaai(model: nil, vectorize_collection_name: true, base_url: nil, dimensions: nil)
          Text2VecJinaConfig.new(
            model: model,
            vectorizeClassName: vectorize_collection_name,
            baseURL: base_url,
            dimensions: dimensions
          )
        end

        # Create a `_Multi2VecJinaConfig` object for use when vectorizing using the `multi2vec-jinaai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/jinaai/embeddings-multimodal)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Deprecated, has no effect.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     dimensions: The number of dimensions for the generated embeddings (only available for some models). Defaults to `None`, which uses the server-defined default.
        #     image_fields: The image fields to use in vectorization.
        #     text_fields: The text fields to use in vectorization.
        def self.multi2vec_jinaai(
          model: nil,
          vectorize_collection_name: true,
          base_url: nil,
          dimensions: nil,
          image_fields: nil,
          text_fields: nil
        )
          Multi2VecJinaConfig.new(
            baseURL: base_url,
            model: model,
            dimensions: dimensions,
            imageFields: Vectorizer.map_multi2vec_fields(image_fields),
            textFields: Vectorizer.map_multi2vec_fields(text_fields)
          )
        end

        # Create a `_Text2VecVoyageConfigCreate` object for use when vectorizing using the `text2vec-voyageai` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/voyageai/embeddings#available-models) for more details.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_voyageai(model: nil, base_url: nil, truncate: nil, vectorize_collection_name: true)
          Text2VecVoyageConfig.new(
            model: model,
            baseURL: base_url,
            truncate: truncate,
            vectorizeClassName: vectorize_collection_name,
            dimensions: nil
          )
        end

        # TODO: add docstrings when the documentation is available.
        def self.text2vec_weaviate(model: nil, base_url: nil, vectorize_collection_name: true, dimensions: nil)
          Text2VecWeaviateConfig.new(
            model: model,
            baseURL: base_url,
            vectorizeClassName: vectorize_collection_name,
            dimensions: dimensions
          )
        end

        # Create a `_Text2VecNvidiaConfigCreate` object for use when vectorizing using the `text2vec-nvidia` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings)
        # for detailed usage.
        #
        # Args:
        #     model: The model to use. Defaults to `None`, which uses the server-defined default.
        #         See the
        #         [documentation](https://weaviate.io/developers/weaviate/model-providers/nvidia/embeddings#available-models) for more details.
        #     base_url: The base URL to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        #     truncate: Whether to truncate the input texts to fit within the context length. Defaults to `None`, which uses the server-defined default.
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        def self.text2vec_nvidia(model: nil, base_url: nil, truncate: nil, vectorize_collection_name: true)
          Text2VecNvidiaConfig.new(
            model: model,
            baseURL: base_url,
            truncate: truncate,
            vectorizeClassName: vectorize_collection_name
          )
        end

        # Create a `_Text2VecModel2VecConfigCreate` object for use when vectorizing using the `text2vec-model2vec` model.
        #
        # See the [documentation](https://weaviate.io/developers/weaviate/model-providers/model2vec/embeddings)
        # for detailed usage.
        #
        # Args:
        #     vectorize_collection_name: Whether to vectorize the collection name. Defaults to `True`.
        #     inference_url: The inference url to use where API requests should go. Defaults to `None`, which uses the server-defined default.
        def self.text2vec_model2vec(inference_url: nil, vectorize_collection_name: true)
          Text2VecModel2VecConfig.new(vectorizeClassName: vectorize_collection_name, inferenceUrl: inference_url)
        end
      end

    end
  end
end
