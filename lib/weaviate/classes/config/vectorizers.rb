# frozen_string_literal: true

require "uri"
require_relative "base"

# Port of weaviate.collections.classes.config_vectorizers: the Vectorizers enum, the
# per-module vectorizer config models and the Multi2VecField helper. The
# `Configure.Vectorizer` factory lives in vectorizers_factory.rb.
module Weaviate
  module Classes
    module Config
      # Python `Literal[...]` type aliases → frozen lists of the allowed values.
      {
        CohereModel: %w[
          embed-v4.0 embed-multilingual-v2.0 embed-multilingual-v3.0 embed-multilingual-light-v3.0 small medium
          large multilingual-22-12 embed-english-v2.0 embed-english-light-v2.0 embed-english-v3.0
          embed-english-light-v3.0
        ],
        CohereMultimodalModel: %w[
          embed-v4.0 embed-multilingual-v3.0 embed-multilingual-light-v3.0 embed-english-v3.0 embed-english-light-v3.0
        ],
        CohereTruncation: %w[NONE START END LEFT RIGHT],
        OpenAIModel: %w[text-embedding-3-small text-embedding-3-large text-embedding-ada-002],
        OpenAIType: %w[text code],
        JinaModel: %w[
          jina-embeddings-v2-base-en jina-embeddings-v2-small-en jina-embeddings-v2-base-zh
          jina-embeddings-v2-base-es jina-embeddings-v2-base-code jina-embeddings-v3 jina-embeddings-v4
        ],
        JinaMultimodalModel: %w[jina-clip-v1 jina-clip-v2 jina-embeddings-v4],
        VoyageModel: %w[
          voyage-4 voyage-4-lite voyage-4-large voyage-3.5 voyage-3.5-lite voyage-3-large voyage-3 voyage-3-lite
          voyage-context-3 voyage-large-2 voyage-code-2 voyage-2 voyage-law-2 voyage-large-2-instruct
          voyage-finance-2 voyage-multilingual-2
        ],
        VoyageMultimodalModel: %w[voyage-multimodal-3 voyage-multimodal-3.5],
        AWSModel: %w[amazon.titan-embed-text-v1 cohere.embed-english-v3 cohere.embed-multilingual-v3],
        AWSService: %w[bedrock sagemaker],
        WeaviateModel: %w[Snowflake/snowflake-arctic-embed-l-v2.0 Snowflake/snowflake-arctic-embed-m-v1.5],
        WeaviateMultimodalModel: %w[ModernVBERT/colmodernvbert]
      }.each { |name, values| const_set(name, values.freeze) unless const_defined?(name, false) }

      # The available vectorization modules in Weaviate.
      module Vectorizers
        extend ::Weaviate::StrEnum

        NONE = "none"
        TEXT2COLBERT_JINAAI = "text2colbert-jinaai"
        TEXT2VEC_AWS = "text2vec-aws"
        TEXT2VEC_COHERE = "text2vec-cohere"
        TEXT2VEC_CONTEXTIONARY = "text2vec-contextionary"
        TEXT2VEC_DATABRICKS = "text2vec-databricks"
        TEXT2VEC_DIGITALOCEAN = "text2vec-digitalocean"
        TEXT2VEC_GPT4ALL = "text2vec-gpt4all"
        TEXT2VEC_HUGGINGFACE = "text2vec-huggingface"
        TEXT2VEC_MISTRAL = "text2vec-mistral"
        TEXT2VEC_MORPH = "text2vec-morph"
        TEXT2VEC_MODEL2VEC = "text2vec-model2vec"
        TEXT2VEC_NVIDIA = "text2vec-nvidia"
        TEXT2VEC_OLLAMA = "text2vec-ollama"
        TEXT2VEC_OPENAI = "text2vec-openai"
        TEXT2VEC_GOOGLE = "text2vec-google"
        TEXT2VEC_PALM = "text2vec-palm" # deprecated, former name of text2vec-google
        TEXT2VEC_TRANSFORMERS = "text2vec-transformers"
        TEXT2VEC_JINAAI = "text2vec-jinaai"
        TEXT2VEC_VOYAGEAI = "text2vec-voyageai"
        TEXT2VEC_WEAVIATE = "text2vec-weaviate"
        IMG2VEC_NEURAL = "img2vec-neural"
        MULTI2VEC_AWS = "multi2vec-aws"
        MULTI2VEC_CLIP = "multi2vec-clip"
        MULTI2VEC_COHERE = "multi2vec-cohere"
        MULTI2VEC_JINAAI = "multi2vec-jinaai"
        MULTI2MULTI_JINAAI = "multi2multivec-jinaai"
        MULTI2MULTI_WEAVIATE = "multi2multivec-weaviate"
        MULTI2VEC_BIND = "multi2vec-bind"
        MULTI2VEC_GOOGLE = "multi2vec-google"
        MULTI2VEC_PALM = "multi2vec-palm" # deprecated, former name of multi2vec-google
        MULTI2VEC_VOYAGEAI = "multi2vec-voyageai"
        MULTI2VEC_NVIDIA = "multi2vec-nvidia"
        MULTI2VEC_TWELVELABS = "multi2vec-twelvelabs"
        REF2VEC_CENTROID = "ref2vec-centroid"
      end

      # Vector similarity distance metric to be used in the `VectorIndexConfig` class.
      module VectorDistances
        extend ::Weaviate::StrEnum

        COSINE = "cosine"
        DOT = "dot"
        L2_SQUARED = "l2-squared"
        HAMMING = "hamming"
        MANHATTAN = "manhattan"
      end

      # Use this class when defining the fields to use in the `Multi2VecClip` and `Multi2VecBind` vectorizers.
      class Multi2VecField < ::Weaviate::Model
        attribute :name
        attribute :weight, default: nil

        def after_initialize
          raise ::Weaviate::Classes::Config::ValidationError,
                "Multi2VecField.name must be a String, got #{name.inspect}" unless name.is_a?(String)
          return if weight.nil? || (weight.is_a?(Numeric) && !weight.is_a?(Complex))

          raise ::Weaviate::Classes::Config::ValidationError,
                "Multi2VecField.weight must be a number, got #{weight.inspect}"
        end

        # `weight` is excluded from the dump (pydantic `Field(exclude=True)`).
        def model_dump(exclude_none: false)
          super.tap { |h| h.delete("weight") }
        end
      end

      # Port of _VectorizerConfigCreate. Fields declared with `field` are type-checked
      # (mirroring pydantic strict mode); `vectorizer` is excluded from #to_dict.
      class VectorizerConfigCreate < ConfigCreateModel
        attribute :vectorizer

        class << self
          # Declare a model field. `type` is one of :str, :int, :bool, :float, :url, :hash,
          # [:list, :str], [:list, Multi2VecField] or [:literal, [allowed values]].
          # `required: true` mirrors a non-Optional pydantic field (nil is rejected).
          def field(name, type, required: false)
            attribute(name, default: required ? ::Weaviate::Model::REQUIRED : nil)
            own_field_types[name.to_sym] = [type, required]
          end

          def field_types
            parent = superclass.respond_to?(:field_types) ? superclass.field_types : {}
            parent.merge(own_field_types)
          end

          # pydantic AnyHttpUrl: validate an http(s) URL and normalise it the way pydantic
          # does (lowercase scheme/host, drop default port, "/" for an empty path).
          def normalize_http_url(value, field_name = "url")
            raise ::Weaviate::Classes::Config::ValidationError,
                  "#{field_name}: URL must be a String, got #{value.inspect}" unless value.is_a?(String)

            uri = begin
              URI.parse(value.strip)
            rescue URI::InvalidURIError => e
              raise ::Weaviate::Classes::Config::ValidationError,
                    "#{field_name}: invalid URL #{value.inspect} (#{e.message})"
            end
            scheme = uri.scheme&.downcase
            unless %w[http https].include?(scheme)
              raise ::Weaviate::Classes::Config::ValidationError,
                    "#{field_name}: URL scheme should be 'http' or 'https', got #{value.inspect}"
            end
            raise ::Weaviate::Classes::Config::ValidationError,
                  "#{field_name}: URL must have a host, got #{value.inspect}" if uri.host.nil? || uri.host.empty?

            out = +"#{scheme}://"
            out << "#{uri.userinfo}@" if uri.userinfo
            out << uri.host.downcase
            out << ":#{uri.port}" if uri.port && uri.port != uri.default_port
            out << (uri.path.nil? || uri.path.empty? ? "/" : uri.path)
            out << "?#{uri.query}" if uri.query
            out << "##{uri.fragment}" if uri.fragment
            out
          end

          private

          def own_field_types
            @own_field_types ||= {}
          end
        end

        def after_initialize
          self.class.field_types.each do |name, (type, required)|
            value = public_send(name)
            if value.nil?
              raise ::Weaviate::Classes::Config::ValidationError,
                    "#{self.class.name}: field '#{name}' is required and cannot be nil" if required

              next
            end
            checked = check_type(name, value, type)
            instance_variable_set(:"@#{name}", checked)
          end
        end

        # Python `_to_dict`: model_dump(exclude_none=True) without the excluded `vectorizer` field.
        def to_dict
          self.class.attribute_names.each_with_object({}) do |name, out|
            next if name == :vectorizer

            value = public_send(name)
            next if value.nil?

            out[name.to_s] = ::Weaviate::Model.dump_value(value, true)
          end
        end

        private

        def check_type(name, value, type)
          ok =
            case type
            when :str then value.is_a?(String)
            when :int then value.is_a?(Integer)
            when :float then value.is_a?(Numeric)
            when :bool then [true, false].include?(value)
            when :hash then value.is_a?(Hash)
            when :url then return self.class.normalize_http_url(value, name.to_s)
            when Array
              kind, arg = type
              case kind
              when :literal then arg.include?(value)
              when :list
                value.is_a?(Array) && value.all? { |v| arg == :str ? v.is_a?(String) : v.is_a?(arg) }
              end
            end
          raise ::Weaviate::Classes::Config::ValidationError,
                "#{self.class.name}: invalid value #{value.inspect} for field '#{name}' (expected #{describe(type)})" unless ok

          value
        end

        def describe(type)
          return type.to_s unless type.is_a?(Array)

          type[0] == :literal ? "one of #{type[1].inspect}" : "list of #{type[1]}"
        end
      end

      # Port of _Text2ColbertJinaAIConfig
      class Text2ColbertJinaAIConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2COLBERT_JINAAI
        field :vectorizeClassName, :bool, required: true
        field :model, :str
        field :dimensions, :int
      end

      # Port of _Text2VecContextionaryConfig
      class Text2VecContextionaryConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_CONTEXTIONARY
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecModel2VecConfig
      class Text2VecModel2VecConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_MODEL2VEC
        field :vectorizeClassName, :bool, required: true
        field :inferenceUrl, :str
      end

      # Port of _VectorizerCustomConfig
      class VectorizerCustomConfig < VectorizerConfigCreate
        field :module_config, :hash

        def to_dict
          module_config.nil? ? {} : module_config
        end
      end

      # Port of _Text2VecAWSConfig
      class Text2VecAWSConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_AWS
        field :model, :str
        field :endpoint, :str
        field :region, :str, required: true
        field :service, :str, required: true
        field :targetModel, :str
        field :targetVariant, :str
        field :dimensions, :int
        field :vectorizeClassName, :bool, required: true

        def after_initialize
          super
          raise ::Weaviate::Classes::Config::ValidationError,
                "region is a required argument and must be given" if region == ""
        end
      end

      # Port of _Text2VecAzureOpenAIConfig
      class Text2VecAzureOpenAIConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_OPENAI
        field :baseURL, :url
        field :resourceName, :str, required: true
        field :deploymentId, :str, required: true
        field :vectorizeClassName, :bool, required: true
        field :dimensions, :int
        field :model, :str

        def to_dict
          super.merge("isAzure" => true)
        end
      end

      # Port of _Text2VecHuggingFaceConfig
      class Text2VecHuggingFaceConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_HUGGINGFACE
        field :model, :str
        field :passageModel, :str
        field :queryModel, :str
        field :endpointURL, :url
        field :waitForModel, :bool
        field :useGPU, :bool
        field :useCache, :bool
        field :vectorizeClassName, :bool, required: true

        def to_dict
          ret = super
          options = {}
          %w[waitForModel useGPU useCache].each { |k| options[k] = ret.delete(k) if ret.key?(k) }
          ret["options"] = options unless options.empty?
          ret
        end
      end

      # Port of _Text2VecMistralConfig
      class Text2VecMistralConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_MISTRAL
        field :model, :str
        field :vectorizeClassName, :bool, required: true
        field :baseURL, :url
      end

      # Port of _Text2VecDigitalOceanConfig
      class Text2VecDigitalOceanConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_DIGITALOCEAN
        field :model, :str, required: true
        field :vectorizeClassName, :bool, required: true
        field :baseURL, :url
      end

      # Port of _Text2VecMorphConfig
      class Text2VecMorphConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_MORPH
        field :model, :str
        field :vectorizeClassName, :bool, required: true
        field :baseURL, :url
        field :endpoint, :str
      end

      # Port of _Text2VecDatabricksConfig
      class Text2VecDatabricksConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_DATABRICKS
        field :endpoint, :str, required: true
        field :instruction, :str
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecOpenAIConfig
      class Text2VecOpenAIConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_OPENAI
        field :baseURL, :url
        field :dimensions, :int
        field :endpoint, :str
        field :model, :str
        field :modelVersion, :str
        field :type_, [:literal, %w[text code]]
        field :vectorizeClassName, :bool, required: true

        def to_dict
          ret = super
          ret["type"] = ret.delete("type_") if ret.key?("type_")
          ret["isAzure"] = false
          ret
        end
      end

      # Port of _Text2VecCohereConfig
      class Text2VecCohereConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_COHERE
        field :baseURL, :url
        field :model, :str
        field :dimensions, :int
        field :truncate, [:literal, CohereTruncation]
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecGoogleConfig
      class Text2VecGoogleConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_GOOGLE
        field :projectId, :str
        field :apiEndpoint, :str
        field :dimensions, :int
        field :modelId, :str
        field :vectorizeClassName, :bool, required: true
        field :titleProperty, :str
        field :taskType, :str
        field :location, :str
      end

      # Port of _Text2VecTransformersConfig
      class Text2VecTransformersConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_TRANSFORMERS
        field :poolingStrategy, [:literal, %w[masked_mean cls]], required: true
        field :vectorizeClassName, :bool, required: true
        field :inferenceUrl, :str
        field :passageInferenceUrl, :str
        field :queryInferenceUrl, :str
        field :dimensions, :int
      end

      # Port of _Text2VecGPT4AllConfig
      class Text2VecGPT4AllConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_GPT4ALL
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecJinaConfig
      class Text2VecJinaConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_JINAAI
        field :baseURL, :str
        field :dimensions, :int
        field :model, :str
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecVoyageConfig
      class Text2VecVoyageConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_VOYAGEAI
        field :dimensions, :int
        field :model, :str
        field :baseURL, :str
        field :truncate, :bool
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecNvidiaConfig
      class Text2VecNvidiaConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_NVIDIA
        field :model, :str
        field :baseURL, :str
        field :truncate, :bool
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Text2VecWeaviateConfig
      class Text2VecWeaviateConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_WEAVIATE
        field :model, :str
        field :baseURL, :str
        field :vectorizeClassName, :bool, required: true
        field :dimensions, :int
      end

      # Port of _Text2VecOllamaConfig
      class Text2VecOllamaConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::TEXT2VEC_OLLAMA
        field :model, :str
        field :apiEndpoint, :str
        field :vectorizeClassName, :bool, required: true
      end

      # Port of _Img2VecNeuralConfig
      class Img2VecNeuralConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::IMG2VEC_NEURAL
        field :imageFields, [:list, :str], required: true
      end

      # Port of _Multi2VecBase
      class Multi2VecBase < VectorizerConfigCreate
        field :imageFields, [:list, Multi2VecField]
        field :textFields, [:list, Multi2VecField]

        def to_dict
          ret = super
          weights = {}
          self.class.attribute_names.each do |name|
            next unless name.to_s.include?("Fields")

            val = public_send(name)
            next if val.nil?

            ret[name.to_s] = val.map(&:name)
            w = val.map(&:weight).compact
            weights[name.to_s] = w unless w.empty?
          end
          ret["weights"] = weights unless weights.empty?
          ret
        end
      end

      # Port of _Multi2VecCohereConfig
      class Multi2VecCohereConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_COHERE
        field :baseURL, :url
        field :model, :str
        field :dimensions, :int
        field :truncate, [:literal, CohereTruncation]
      end

      # Port of _Multi2VecJinaConfig
      class Multi2VecJinaConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_JINAAI
        field :baseURL, :url
        field :model, :str
        field :dimensions, :int
      end

      # Port of _Multi2VecAWSConfig
      class Multi2VecAWSConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_AWS
        field :region, :str
        field :model, :str
        field :dimensions, :int
      end

      # Port of _Multi2MultiVecJinaConfig
      class Multi2MultiVecJinaConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2MULTI_JINAAI
        field :baseURL, :url
        field :model, :str
      end

      # Port of _Multi2MultiVecWeaviateConfig
      class Multi2MultiVecWeaviateConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2MULTI_WEAVIATE
        field :baseURL, :url
        field :model, :str
      end

      # Port of _Multi2VecClipConfig
      class Multi2VecClipConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_CLIP
        field :inferenceUrl, :str
      end

      # Port of _Multi2VecGoogleConfig
      class Multi2VecGoogleConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_GOOGLE
        field :audioFields, [:list, Multi2VecField]
        field :videoFields, [:list, Multi2VecField]
        field :projectId, :str
        field :location, :str
        field :apiEndpoint, :str
        field :modelId, :str
        field :dimensions, :int
        field :videoIntervalSeconds, :int
      end

      # Port of _Multi2VecBindConfig
      class Multi2VecBindConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_BIND
        field :audioFields, [:list, Multi2VecField]
        field :depthFields, [:list, Multi2VecField]
        field :IMUFields, [:list, Multi2VecField]
        field :thermalFields, [:list, Multi2VecField]
        field :videoFields, [:list, Multi2VecField]
      end

      # Port of _Multi2VecVoyageaiConfig
      class Multi2VecVoyageaiConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_VOYAGEAI
        field :baseURL, :url
        field :model, :str
        field :truncation, :bool
        field :dimensions, :int
        field :videoFields, [:list, Multi2VecField]
      end

      # Port of _Multi2VecNvidiaConfig
      class Multi2VecNvidiaConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_NVIDIA
        field :baseURL, :url
        field :model, :str
        field :truncation, :bool
      end

      # Port of _Multi2VecTwelvelabsConfig
      class Multi2VecTwelvelabsConfig < Multi2VecBase
        attribute :vectorizer, default: Vectorizers::MULTI2VEC_TWELVELABS
        field :baseURL, :url
        field :model, :str
      end

      # Port of _Ref2VecCentroidConfig
      class Ref2VecCentroidConfig < VectorizerConfigCreate
        attribute :vectorizer, default: Vectorizers::REF2VEC_CENTROID
        field :referenceProperties, [:list, :str], required: true
        field :method, [:literal, %w[mean]], required: true

        # The `method` field shadows Object#method; keep Object#method(name) working.
        remove_method :method
        def method(*args)
          args.empty? ? @method : super
        end
      end
    end
  end
end
