# frozen_string_literal: true

require_relative "../cluster/models"

module Weaviate
  module Outputs
    # Port of weaviate.outputs.replication
    module Replication
      ReplicateOperation = ::Weaviate::Cluster::ReplicateOperation
      ReplicateOperationWithHistory = ::Weaviate::Cluster::ReplicateOperationWithHistory
      ReplicateOperationWithoutHistory = ::Weaviate::Cluster::ReplicateOperationWithoutHistory
      ReplicateOperationState = ::Weaviate::Cluster::ReplicateOperationState
      ReplicateOperationStatus = ::Weaviate::Cluster::ReplicateOperationStatus
    end
  end
end
