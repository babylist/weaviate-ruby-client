# frozen_string_literal: true

require_relative "../../classes/data/types"

module Weaviate
  module Outputs
    # Return types of the `.query` namespace (port of weaviate.collections.classes.internal).
    module Query
      # Metadata of an object returned by a query.
      class MetadataReturn < ::Weaviate::Model
        attributes :creation_time, :last_update_time, :distance, :certainty, :score, :explain_score, :is_consistent,
                   :rerank_score

        def is_empty # rubocop:disable Naming/PredicatePrefix
          to_h.values.all?(&:nil?)
        end
        alias empty? is_empty
      end

      # Profiling details for a single search type within a shard.
      class SearchProfileReturn < ::Weaviate::Model
        attribute :details
      end

      # Profiling data for a single shard.
      class ShardProfileReturn < ::Weaviate::Model
        attribute :name
        attribute :node
        attribute :searches
      end

      # Per-shard query profiling data returned when `query_profile: true` is set in the metadata.
      class QueryProfileReturn < ::Weaviate::Model
        attribute :shards
      end

      # Metadata of an object returned by a group by query.
      class GroupByMetadataReturn < ::Weaviate::Model
        attribute :distance, default: nil
      end

      # A single Weaviate object returned by a query within the `.query` namespace of a collection.
      class Object < ::Weaviate::Model
        attribute :uuid
        attribute :metadata
        attribute :properties
        attribute :references
        attribute :vector
        attribute :collection
      end

      # Metadata of an object returned by the `fetch_object_by_id` query.
      class MetadataSingleObjectReturn < ::Weaviate::Model
        attribute :creation_time
        attribute :last_update_time
        attribute :is_consistent
      end

      # A single Weaviate object returned by the `fetch_object_by_id` query.
      class ObjectSingleReturn < ::Weaviate::Model
        attribute :uuid
        attribute :metadata
        attribute :properties
        attribute :references
        attribute :vector
        attribute :collection
      end

      # A single Weaviate object returned by a query with the `group_by` argument specified.
      class GroupByObject < ::Weaviate::Model
        attribute :uuid
        attribute :metadata
        attribute :properties
        attribute :references
        attribute :vector
        attribute :collection
        attribute :belongs_to_group
      end

      # A group of objects returned in a group by query.
      class Group < ::Weaviate::Model
        attribute :name
        attribute :min_distance
        attribute :max_distance
        attribute :number_of_objects
        attribute :objects
        attribute :rerank_score
      end

      # The return type of a query within the `.query` namespace with the `group_by` argument specified.
      class GroupByReturn < ::Weaviate::Model
        attribute :objects
        attribute :groups
        attribute :query_profile, default: nil
      end

      # The return type of a query within the `.query` namespace of a collection.
      class QueryReturn < ::Weaviate::Model
        attribute :objects
        attribute :query_profile, default: nil
      end

      # The objects of a cross reference returned by a query (Python _CrossReference).
      class CrossReference
        def initialize(objects)
          @objects = objects
        end

        def self.from(objects) = new(objects)

        def objects = @objects || []

        def ==(other) = other.is_a?(CrossReference) && other.objects == objects

        def inspect = "#<#{self.class.name} objects=#{objects.inspect}>"
      end

      # Output of the phoneNumber datatype (Python _PhoneNumber / PhoneNumberType). Python has a single
      # class, so this is the same class as Classes::Data::PhoneNumberType (the insert guard checks that one).
      PhoneNumberType = ::Weaviate::Classes::Data::PhoneNumberType
    end
  end
end
