# frozen_string_literal: true

module Weaviate
  module Classes
    module Query
      # Use this class when you want to insert a multi-target reference property
      # (also exposed as Weaviate::Classes::Data::ReferenceToMulti).
      class ReferenceToMulti < ::Weaviate::Model
        attribute :target_collection
        attribute :uuids

        def to_beacons
          ::Weaviate::Util.to_beacons(uuids_str, target_collection)
        end

        # Returns the UUIDs as strings.
        def uuids_str
          uuids.is_a?(Array) ? uuids.map(&:to_s) : [uuids.to_s]
        end
      end

      # Python _Reference. You should not initialise this class directly.
      class Reference
        def initialize(target_collection, uuids)
          @target_collection = target_collection || ""
          @uuids = uuids
        end

        def to_beacons
          ::Weaviate::Util.to_beacons(@uuids, @target_collection)
        end

        # True if the reference points to more than one object.
        def is_one_to_many # rubocop:disable Naming/PredicatePrefix
          !@uuids.nil? && @uuids.is_a?(Array) && @uuids.length > 1
        end
        alias one_to_many? is_one_to_many
      end
    end
  end
end
