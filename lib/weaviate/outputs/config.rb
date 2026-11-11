# frozen_string_literal: true

require_relative "../classes/config/enums"
require_relative "../classes/config/config_outputs"

module Weaviate
  module Outputs
    # Mirrors weaviate.outputs.config (`Vectorizers` and `VectorDistances` belong to the vectorizer
    # port and are not aliased here).
    module Config
      AsyncReplicationConfig = ::Weaviate::Classes::Config::AsyncReplicationConfig
      BM25Config = ::Weaviate::Classes::Config::BM25Config
      CollectionConfig = ::Weaviate::Classes::Config::CollectionConfig
      CollectionConfigSimple = ::Weaviate::Classes::Config::CollectionConfigSimple
      GenerativeConfig = ::Weaviate::Classes::Config::GenerativeConfig
      GenerativeSearches = ::Weaviate::Classes::Config::GenerativeSearches
      InvertedIndexConfig = ::Weaviate::Classes::Config::InvertedIndexConfig
      MultiTenancyConfig = ::Weaviate::Classes::Config::MultiTenancyConfig
      ReplicationDeletionStrategy = ::Weaviate::Classes::Config::ReplicationDeletionStrategy
      PQConfig = ::Weaviate::Classes::Config::PQConfig
      PQEncoderConfig = ::Weaviate::Classes::Config::PQEncoderConfig
      PQEncoderDistribution = ::Weaviate::Classes::Config::PQEncoderDistribution
      PQEncoderType = ::Weaviate::Classes::Config::PQEncoderType
      PropertyConfig = ::Weaviate::Classes::Config::PropertyConfig
      ReferencePropertyConfig = ::Weaviate::Classes::Config::ReferencePropertyConfig
      ReplicationConfig = ::Weaviate::Classes::Config::ReplicationConfig
      Rerankers = ::Weaviate::Classes::Config::Rerankers
      RerankerConfig = ::Weaviate::Classes::Config::RerankerConfig
      ShardingConfig = ::Weaviate::Classes::Config::ShardingConfig
      ShardStatus = ::Weaviate::Classes::Config::ShardStatus
      ShardTypes = ::Weaviate::Classes::Config::ShardTypes
      VectorIndexConfigHNSW = ::Weaviate::Classes::Config::VectorIndexConfigHNSW
      VectorIndexConfigHFresh = ::Weaviate::Classes::Config::VectorIndexConfigHFresh
      VectorIndexConfigFlat = ::Weaviate::Classes::Config::VectorIndexConfigFlat
      VectorIndexConfigNone = ::Weaviate::Classes::Config::VectorIndexConfigNone
      VectorIndexType = ::Weaviate::Classes::Config::VectorIndexType
      VectorizerConfig = ::Weaviate::Classes::Config::VectorizerConfig
      VectorDistances = ::Weaviate::Classes::Config::VectorDistances
      Vectorizers = ::Weaviate::Classes::Config::Vectorizers
    end
  end
end
