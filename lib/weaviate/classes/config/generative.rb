# frozen_string_literal: true

require_relative "base"
require_relative "enums"
require_relative "fields"

# Generative and reranker module configs from weaviate/collections/classes/config.py
module Weaviate
  module Classes
    module Config
      GENERATIVE_SPEC = [:union, GenerativeSearches, EnumLikeStr].freeze
      RERANKER_SPEC = [:union, Rerankers, EnumLikeStr].freeze

      # GenerativeProvider
      class GenerativeProvider < ConfigCreateModel
        include Fields

        field :generative, GENERATIVE_SPEC, required: true

        # Provider fields typed as pydantic AnyHttpUrl.
        def self.http_url_fields
          []
        end

        def after_initialize
          self.class.http_url_fields.each do |f|
            value = public_send(f)
            public_send(:"#{f}=", ConfigHelpers.http_url(value, f.to_s)) unless value.nil?
          end
          super
        end
      end

      # Helper to declare the fixed, excluded `generative` field of a provider.
      module GenerativeModule
        def generative_module(value)
          field :generative, GENERATIVE_SPEC, default: value, exclude: true
        end
      end
      GenerativeProvider.extend(GenerativeModule)

      class GenerativeAnyscale < GenerativeProvider
        generative_module GenerativeSearches::ANYSCALE
        field :baseURL, :str
        field :temperature, :float
        field :model, :str
      end

      class GenerativeCustom < GenerativeProvider
        field :module_config, :hash

        def to_dict
          module_config.nil? ? {} : module_config
        end
      end

      class GenerativeDatabricks < GenerativeProvider
        generative_module GenerativeSearches::DATABRICKS
        field :endpoint, :str, required: true
        field :maxTokens, :int
        field :temperature, :float
        field :topK, :int
        field :topP, :float
      end

      class GenerativeDeepseek < GenerativeProvider
        generative_module GenerativeSearches::DEEPSEEK
        field :model, :str
        field :temperature, :float
        field :maxTokens, :int
        field :frequencyPenalty, :float
        field :presencePenalty, :float
        field :topP, :float
        field :baseURL, :str
        field :stop, [:list, :str]
      end

      class GenerativeDigitalOcean < GenerativeProvider
        generative_module GenerativeSearches::DIGITALOCEAN
        field :baseURL, :str
        field :model, :str
        field :temperature, :float
        field :topP, :float
        field :maxTokens, :int
        field :frequencyPenalty, :float
        field :presencePenalty, :float
        field :stop, [:list, :str]
      end

      class GenerativeMeta < GenerativeProvider
        generative_module GenerativeSearches::META
        field :baseURL, :str
        field :model, :str
        field :temperature, :float
        field :topP, :float
        field :maxTokens, :int
        field :frequencyPenalty, :float
        field :presencePenalty, :float
        field :reasoningEffort, :str
      end

      class GenerativeMistral < GenerativeProvider
        generative_module GenerativeSearches::MISTRAL
        field :temperature, :float
        field :model, :str
        field :maxTokens, :int
        field :baseURL, :str
      end

      class GenerativeNvidia < GenerativeProvider
        generative_module GenerativeSearches::NVIDIA
        field :temperature, :float
        field :model, :str
        field :maxTokens, :int
        field :baseURL, :str
        field :topP, :float
      end

      class GenerativeXai < GenerativeProvider
        generative_module GenerativeSearches::XAI
        field :temperature, :float
        field :model, :str
        field :maxTokens, :int
        field :baseURL, :str
        field :topP, :float
      end

      class GenerativeFriendliai < GenerativeProvider
        generative_module GenerativeSearches::FRIENDLIAI
        field :temperature, :float
        field :model, :str
        field :maxTokens, :int
        field :baseURL, :str
      end

      class GenerativeOllama < GenerativeProvider
        generative_module GenerativeSearches::OLLAMA
        field :model, :str
        field :apiEndpoint, :str
      end

      class GenerativeOpenAIConfigBase < GenerativeProvider
        generative_module GenerativeSearches::OPENAI
        field :baseURL, :str
        field :frequencyPenalty, :float
        field :presencePenalty, :float
        field :maxTokens, :int
        field :temperature, :float
        field :topP, :float

        def self.http_url_fields = [:baseURL]
      end

      class GenerativeOpenAIConfig < GenerativeOpenAIConfigBase
        field :model, :str
        field :verbosity, :str
        field :reasoningEffort, :str
      end

      class GenerativeAzureOpenAIConfig < GenerativeOpenAIConfigBase
        field :resourceName, :str, required: true
        field :deploymentId, :str, required: true
        field :apiVersion, :str
      end

      class GenerativeCohereConfig < GenerativeProvider
        generative_module GenerativeSearches::COHERE
        field :baseURL, :str
        field :k, :int
        field :model, :str
        field :maxTokens, :int
        field :stopSequences, [:list, :str]
        field :temperature, :float

        def self.http_url_fields = [:baseURL]
      end

      class GenerativeContextualAIConfig < GenerativeProvider
        generative_module GenerativeSearches::CONTEXTUALAI
        field :model, :str
        field :temperature, :float
        field :topP, :float
        field :maxNewTokens, :int
        field :systemPrompt, :str
        field :avoidCommentary, :bool
        field :knowledge, [:list, :str]
      end

      class GenerativeGoogleConfig < GenerativeProvider
        generative_module GenerativeSearches::PALM
        field :apiEndpoint, :str
        field :endpointId, :str
        field :region, :str
        field :location, :str
        field :maxOutputTokens, :int
        field :modelId, :str
        field :projectId, :str, required: true
        field :temperature, :float
        field :topK, :int
        field :topP, :float
        field :stopSequences, [:list, :str]
        field :frequencyPenalty, :float
        field :presencePenalty, :float
      end

      class GenerativeAWSConfig < GenerativeProvider
        generative_module GenerativeSearches::AWS
        field :region, :str, required: true
        field :service, :str, required: true
        field :model, :str
        field :endpoint, :str
        field :temperature, :float
        field :targetModel, :str
        field :targetVariant, :str
        field :topK, :int
        field :topP, :float
        field :stopSequences, [:list, :str]
        field :maxTokens, :int
      end

      class GenerativeAnthropicConfig < GenerativeProvider
        generative_module GenerativeSearches::ANTHROPIC
        field :model, :str
        field :maxTokens, :int
        field :stopSequences, [:list, :str]
        field :temperature, :float
        field :topK, :int
        field :topP, :float
        field :baseURL, :str
      end

      # RerankerProvider
      class RerankerProvider < ConfigCreateModel
        include Fields

        field :reranker, RERANKER_SPEC, required: true

        def self.http_url_fields
          []
        end

        def after_initialize
          self.class.http_url_fields.each do |f|
            value = public_send(f)
            public_send(:"#{f}=", ConfigHelpers.http_url(value, f.to_s)) unless value.nil?
          end
          super
        end
      end

      # Helper to declare the fixed, excluded `reranker` field of a provider.
      module RerankerModule
        def reranker_module(value)
          field :reranker, RERANKER_SPEC, default: value, exclude: true
        end
      end
      RerankerProvider.extend(RerankerModule)

      class RerankerCohereConfig < RerankerProvider
        reranker_module Rerankers::COHERE
        field :model, :str
        field :baseURL, :str

        def self.http_url_fields = [:baseURL]
      end

      class RerankerCustomConfig < RerankerProvider
        field :module_config, :hash

        def to_dict
          module_config.nil? ? {} : module_config
        end
      end

      class RerankerTransformersConfig < RerankerProvider
        reranker_module Rerankers::TRANSFORMERS
      end

      class RerankerJinaAIConfig < RerankerProvider
        reranker_module Rerankers::JINAAI
        field :model, :str
      end

      class RerankerVoyageAIConfig < RerankerProvider
        reranker_module Rerankers::VOYAGEAI
        field :model, :str
      end

      class RerankerNvidiaConfig < RerankerProvider
        reranker_module Rerankers::NVIDIA
        field :model, :str
        field :baseURL, :str

        def self.http_url_fields = [:baseURL]
      end

      class RerankerContextualAIConfig < RerankerProvider
        reranker_module Rerankers::CONTEXTUALAI
        field :model, :str
        field :instruction, :str
        field :topN, :int
      end

      # _Generative (Configure.Generative / Reconfigure.Generative)
      module Generative
        module_function

        def anyscale(model: nil, temperature: nil, base_url: nil)
          GenerativeAnyscale.new(model: model, temperature: temperature, baseURL: base_url)
        end

        def custom(module_name, module_config: nil)
          GenerativeCustom.new(generative: EnumLikeStr.new(string: module_name), module_config: module_config)
        end

        def databricks(endpoint:, max_tokens: nil, temperature: nil, top_k: nil, top_p: nil)
          GenerativeDatabricks.new(endpoint: endpoint, maxTokens: max_tokens, temperature: temperature, topK: top_k,
                                   topP: top_p)
        end

        def deepseek(base_url: nil, model: nil, temperature: nil, max_tokens: nil, frequency_penalty: nil,
                     presence_penalty: nil, top_p: nil, stop: nil)
          GenerativeDeepseek.new(model: model, temperature: temperature, maxTokens: max_tokens,
                                 frequencyPenalty: frequency_penalty, presencePenalty: presence_penalty, topP: top_p,
                                 baseURL: base_url, stop: stop)
        end

        def digitalocean(base_url: nil, model: nil, temperature: nil, top_p: nil, max_tokens: nil,
                         frequency_penalty: nil, presence_penalty: nil, stop: nil)
          GenerativeDigitalOcean.new(baseURL: base_url, model: model, temperature: temperature, topP: top_p,
                                     maxTokens: max_tokens, frequencyPenalty: frequency_penalty,
                                     presencePenalty: presence_penalty, stop: stop)
        end

        def friendliai(base_url: nil, model: nil, temperature: nil, max_tokens: nil)
          GenerativeFriendliai.new(model: model, temperature: temperature, maxTokens: max_tokens, baseURL: base_url)
        end

        def meta(base_url: nil, model: nil, temperature: nil, top_p: nil, max_tokens: nil, frequency_penalty: nil,
                 presence_penalty: nil, reasoning_effort: nil)
          GenerativeMeta.new(baseURL: base_url, model: model, temperature: temperature, topP: top_p,
                             maxTokens: max_tokens, frequencyPenalty: frequency_penalty,
                             presencePenalty: presence_penalty, reasoningEffort: reasoning_effort)
        end

        def mistral(model: nil, temperature: nil, max_tokens: nil, base_url: nil)
          GenerativeMistral.new(model: model, temperature: temperature, maxTokens: max_tokens, baseURL: base_url)
        end

        def nvidia(base_url: nil, model: nil, temperature: nil, max_tokens: nil, top_p: nil)
          GenerativeNvidia.new(model: model, temperature: temperature, maxTokens: max_tokens, baseURL: base_url,
                               topP: top_p)
        end

        def xai(base_url: nil, model: nil, temperature: nil, max_tokens: nil, top_p: nil)
          GenerativeXai.new(model: model, temperature: temperature, maxTokens: max_tokens, topP: top_p,
                            baseURL: base_url)
        end

        def ollama(api_endpoint: nil, model: nil)
          GenerativeOllama.new(model: model, apiEndpoint: api_endpoint)
        end

        def openai(model: nil, frequency_penalty: nil, max_tokens: nil, presence_penalty: nil, temperature: nil,
                   top_p: nil, base_url: nil, verbosity: nil, reasoning_effort: nil)
          GenerativeOpenAIConfig.new(baseURL: base_url, frequencyPenalty: frequency_penalty, maxTokens: max_tokens,
                                     model: model, presencePenalty: presence_penalty, temperature: temperature,
                                     topP: top_p, verbosity: verbosity, reasoningEffort: reasoning_effort)
        end

        def azure_openai(resource_name, deployment_id:, frequency_penalty: nil, max_tokens: nil,
                         presence_penalty: nil, temperature: nil, top_p: nil, base_url: nil, api_version: nil)
          GenerativeAzureOpenAIConfig.new(apiVersion: api_version, baseURL: base_url, deploymentId: deployment_id,
                                          frequencyPenalty: frequency_penalty, maxTokens: max_tokens,
                                          presencePenalty: presence_penalty, resourceName: resource_name,
                                          temperature: temperature, topP: top_p)
        end

        # `return_likelihoods` is deprecated in Python and has no effect.
        def cohere(model: nil, k: nil, max_tokens: nil, return_likelihoods: nil, stop_sequences: nil, # rubocop:disable Lint/UnusedMethodArgument
                   temperature: nil, base_url: nil)
          GenerativeCohereConfig.new(baseURL: base_url, k: k, maxTokens: max_tokens, model: model,
                                     stopSequences: stop_sequences, temperature: temperature)
        end

        def contextualai(model: nil, max_new_tokens: nil, temperature: nil, top_p: nil, system_prompt: nil,
                         avoid_commentary: nil, knowledge: nil)
          GenerativeContextualAIConfig.new(model: model, temperature: temperature, topP: top_p,
                                           maxNewTokens: max_new_tokens, systemPrompt: system_prompt,
                                           avoidCommentary: avoid_commentary, knowledge: knowledge)
        end

        # Deprecated in Python (to be removed after Q3 '26): use google_vertex or google_gemini.
        def google(project_id, api_endpoint: nil, max_output_tokens: nil, model_id: nil, temperature: nil, top_k: nil,
                   top_p: nil)
          GenerativeGoogleConfig.new(apiEndpoint: api_endpoint, region: nil, location: nil,
                                     maxOutputTokens: max_output_tokens, modelId: model_id, projectId: project_id,
                                     endpointId: nil, temperature: temperature, topK: top_k, topP: top_p,
                                     stopSequences: nil, frequencyPenalty: nil, presencePenalty: nil)
        end

        def google_vertex(project_id, api_endpoint: nil, region: nil, max_output_tokens: nil, model_id: nil,
                          endpoint_id: nil, temperature: nil, top_k: nil, top_p: nil, location: nil)
          GenerativeGoogleConfig.new(apiEndpoint: api_endpoint, region: region, location: location,
                                     maxOutputTokens: max_output_tokens, modelId: model_id, projectId: project_id,
                                     endpointId: endpoint_id, temperature: temperature, topK: top_k, topP: top_p,
                                     stopSequences: nil, frequencyPenalty: nil, presencePenalty: nil)
        end

        def google_gemini(max_output_tokens: nil, model: nil, temperature: nil, top_k: nil, top_p: nil)
          GenerativeGoogleConfig.new(apiEndpoint: nil, region: nil, location: nil,
                                     maxOutputTokens: max_output_tokens, modelId: model, projectId: "",
                                     endpointId: nil, temperature: temperature, topK: top_k, topP: top_p,
                                     stopSequences: nil, frequencyPenalty: nil, presencePenalty: nil)
        end

        # Deprecated in Python (to be removed after Q3 '26): use aws_bedrock or aws_sagemaker.
        def aws(model: nil, region: "", endpoint: nil, service: "bedrock", max_tokens: nil)
          GenerativeAWSConfig.new(model: model, region: region, service: service, endpoint: endpoint,
                                  temperature: nil, maxTokens: max_tokens, targetModel: nil, targetVariant: nil,
                                  topK: nil, topP: nil, stopSequences: nil)
        end

        def aws_bedrock(model, region:, temperature: nil, max_tokens: nil, top_k: nil, top_p: nil,
                        stop_sequences: nil)
          GenerativeAWSConfig.new(model: model, region: region, service: "bedrock", endpoint: nil,
                                  temperature: temperature, maxTokens: max_tokens, targetModel: nil,
                                  targetVariant: nil, topK: top_k, topP: top_p, stopSequences: stop_sequences)
        end

        def aws_sagemaker(region, endpoint:, max_tokens: nil, target_model: nil, target_variant: nil,
                          temperature: nil, top_k: nil, top_p: nil, stop_sequences: nil)
          GenerativeAWSConfig.new(model: nil, region: region, service: "sagemaker", endpoint: endpoint,
                                  temperature: temperature, maxTokens: max_tokens, targetModel: target_model,
                                  targetVariant: target_variant, topK: top_k, topP: top_p,
                                  stopSequences: stop_sequences)
        end

        def anthropic(model: nil, max_tokens: nil, stop_sequences: nil, temperature: nil, top_k: nil, top_p: nil,
                      base_url: nil)
          GenerativeAnthropicConfig.new(model: model, maxTokens: max_tokens, stopSequences: stop_sequences,
                                        temperature: temperature, topK: top_k, topP: top_p, baseURL: base_url)
        end
      end

      # _Reranker (Configure.Reranker / Reconfigure.Reranker)
      module Reranker
        module_function

        def transformers
          RerankerTransformersConfig.new(reranker: Rerankers::TRANSFORMERS)
        end

        def custom(module_name, module_config: nil)
          RerankerCustomConfig.new(reranker: EnumLikeStr.new(string: module_name), module_config: module_config)
        end

        def cohere(model: nil, base_url: nil)
          RerankerCohereConfig.new(model: model, baseURL: base_url)
        end

        def jinaai(model: nil)
          RerankerJinaAIConfig.new(model: model)
        end

        def voyageai(model: nil)
          RerankerVoyageAIConfig.new(model: model)
        end

        def nvidia(model: nil, base_url: nil)
          RerankerNvidiaConfig.new(model: model, baseURL: base_url)
        end

        def contextualai(model: nil, instruction: nil, top_n: nil)
          RerankerContextualAIConfig.new(model: model, instruction: instruction, topN: top_n)
        end
      end
    end
  end
end
