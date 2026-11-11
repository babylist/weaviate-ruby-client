# frozen_string_literal: true

require_relative "../cluster/models"

module Weaviate
  module Classes
    # Port of weaviate.classes.replication
    module Replication
      ReplicationType = ::Weaviate::Cluster::ReplicationType
    end
  end
end
