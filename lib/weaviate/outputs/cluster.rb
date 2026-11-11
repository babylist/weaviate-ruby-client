# frozen_string_literal: true

require_relative "../cluster/models"

module Weaviate
  module Outputs
    # Port of weaviate.outputs.cluster
    module Cluster
      ClusterStatistics = ::Weaviate::Cluster::ClusterStatistics
      Node = ::Weaviate::Cluster::Node
      NodeMinimal = ::Weaviate::Cluster::NodeMinimal
      NodeStatistics = ::Weaviate::Cluster::NodeStatistics
      NodeVerbose = ::Weaviate::Cluster::NodeVerbose
      RaftConfigurationMember = ::Weaviate::Cluster::RaftConfigurationMember
      RaftStats = ::Weaviate::Cluster::RaftStats
      Shard = ::Weaviate::Cluster::Shard
      ShardingState = ::Weaviate::Cluster::ShardingState
      ShardReplicas = ::Weaviate::Cluster::ShardReplicas
      Stats = ::Weaviate::Cluster::Stats
    end
  end
end
