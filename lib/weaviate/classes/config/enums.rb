# frozen_string_literal: true

module Weaviate
  module Classes
    module Config
      # Port of weaviate.collections.classes.config.ConsistencyLevel
      module ConsistencyLevel
        extend ::Weaviate::StrEnum

        ALL = "ALL"
        ONE = "ONE"
        QUORUM = "QUORUM"
      end

      # Port of DataType
      module DataType
        extend ::Weaviate::StrEnum

        TEXT = "text"
        TEXT_ARRAY = "text[]"
        INT = "int"
        INT_ARRAY = "int[]"
        BOOL = "boolean"
        BOOL_ARRAY = "boolean[]"
        NUMBER = "number"
        NUMBER_ARRAY = "number[]"
        DATE = "date"
        DATE_ARRAY = "date[]"
        UUID = "uuid"
        UUID_ARRAY = "uuid[]"
        GEO_COORDINATES = "geoCoordinates"
        BLOB = "blob"
        BLOB_HASH = "blobHash"
        PHONE_NUMBER = "phoneNumber"
        OBJECT = "object"
        OBJECT_ARRAY = "object[]"
      end

      # Port of Tokenization
      module Tokenization
        extend ::Weaviate::StrEnum

        WORD = "word"
        WHITESPACE = "whitespace"
        LOWERCASE = "lowercase"
        FIELD = "field"
        GSE = "gse"
        TRIGRAM = "trigram"
        KAGOME_JA = "kagome_ja"
        KAGOME_KR = "kagome_kr"
        GSE_CH = "gse_ch"
      end

      # Port of GenerativeSearches
      module GenerativeSearches
        extend ::Weaviate::StrEnum

        AWS = "generative-aws"
        ANTHROPIC = "generative-anthropic"
        ANYSCALE = "generative-anyscale"
        COHERE = "generative-cohere"
        CONTEXTUALAI = "generative-contextualai"
        DATABRICKS = "generative-databricks"
        DEEPSEEK = "generative-deepseek"
        DIGITALOCEAN = "generative-digitalocean"
        DUMMY = "generative-dummy"
        FRIENDLIAI = "generative-friendliai"
        META = "generative-meta"
        MISTRAL = "generative-mistral"
        NVIDIA = "generative-nvidia"
        OLLAMA = "generative-ollama"
        OPENAI = "generative-openai"
        PALM = "generative-palm" # rename to google once all versions support it
        XAI = "generative-xai"
      end

      # Port of Rerankers
      module Rerankers
        extend ::Weaviate::StrEnum

        NONE = "none"
        COHERE = "reranker-cohere"
        CONTEXTUALAI = "reranker-contextualai"
        TRANSFORMERS = "reranker-transformers"
        VOYAGEAI = "reranker-voyageai"
        JINAAI = "reranker-jinaai"
        NVIDIA = "reranker-nvidia"
      end

      # Port of StopwordsPreset
      module StopwordsPreset
        extend ::Weaviate::StrEnum

        NONE = "none"
        EN = "en"
      end

      # Port of ReplicationDeletionStrategy
      module ReplicationDeletionStrategy
        extend ::Weaviate::StrEnum

        DELETE_ON_CONFLICT = "DeleteOnConflict"
        NO_AUTOMATED_RESOLUTION = "NoAutomatedResolution"
        TIME_BASED_RESOLUTION = "TimeBasedResolution"
      end

      # Port of config_vector_index.VectorFilterStrategy
      module VectorFilterStrategy
        extend ::Weaviate::StrEnum

        SWEEPING = "sweeping"
        ACORN = "acorn"
        PATHSEER = "pathseer"
      end

      # Port of config_vector_index.VectorIndexType
      module VectorIndexType
        extend ::Weaviate::StrEnum

        HNSW = "hnsw"
        FLAT = "flat"
        DYNAMIC = "dynamic"
        HFRESH = "hfresh"
        NONE = "none"
      end

      # Port of config_vector_index.PQEncoderType
      module PQEncoderType
        extend ::Weaviate::StrEnum

        KMEANS = "kmeans"
        TILE = "tile"
      end

      # Port of config_vector_index.PQEncoderDistribution
      module PQEncoderDistribution
        extend ::Weaviate::StrEnum

        LOG_NORMAL = "log-normal"
        NORMAL = "normal"
      end

      # Port of config_vector_index.MultiVectorAggregation
      module MultiVectorAggregation
        extend ::Weaviate::StrEnum

        MAX_SIM = "maxSim"
      end

      # Python `Literal[...]` type aliases → frozen lists of the allowed values.
      AWSService = %w[bedrock sagemaker].freeze
      OpenAiVerbosity = %w[low medium high].freeze
      OpenAiReasoningEffort = %w[minimal low medium high].freeze
      MetaReasoningEffort = %w[none minimal low medium high xhigh].freeze
      IndexName = %w[searchable filterable rangeFilters].freeze
      RerankerCohereModel = %w[rerank-english-v2.0 rerank-multilingual-v2.0].freeze
      RerankerJinaAIModel = %w[
        jina-reranker-v2-base-multilingual
        jina-reranker-v1-base-en
        jina-reranker-v1-turbo-en
        jina-reranker-v1-tiny-en
        jina-colbert-v1-en
      ].freeze
      RerankerVoyageAIModel = %w[rerank-2 rerank-2-lite rerank-lite-1 rerank-1].freeze
      RerankerContextualAIModel = %w[
        ctxl-rerank-v2-instruct-multilingual
        ctxl-rerank-v2-instruct-multilingual-mini
        ctxl-rerank-v1-instruct
      ].freeze
      ShardTypes = %w[READONLY READY INDEXING LOADING LAZY_LOADING SHUTDOWN UNAVAILABLE RECOVERING].freeze
    end
  end
end
