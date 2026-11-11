# frozen_string_literal: true

module Weaviate
  module Classes
    module Data
      BEACON = "weaviate://localhost/"

      # Port of weaviate.collections.classes.data.DataObject: an entire object within a collection to be used
      # when batching (e.g. `collection.data.insert_many`).
      class DataObject < ::Weaviate::Model
        attribute :properties, default: nil
        attribute :uuid, default: nil
        attribute :vector, default: nil
        attribute :references, default: nil
      end

      # Port of weaviate.collections.classes.data._DataReference
      class DataReferenceBase < ::Weaviate::Model
        attribute :from_property
        attribute :from_uuid
        attribute :to_uuid

        # Python `_to_uuids`
        def to_uuids
          to_uuid.is_a?(Array) ? to_uuid : [to_uuid]
        end
      end

      # A reference to a multi-target reference property, used when batching references.
      class DataReferenceMulti < DataReferenceBase
        attribute :target_collection

        # Python `_to_beacons`
        def to_beacons
          to_uuids.map { |uuid| "#{BEACON}#{target_collection}/#{uuid}" }
        end
      end

      # A reference between objects within a collection to be used when batching references.
      class DataReference < DataReferenceBase
        MultiTarget = DataReferenceMulti

        def to_beacons
          to_uuids.map { |uuid| "#{BEACON}#{uuid}" }
        end
      end

      # Python `DataReferences` type alias.
      DataReferences = [DataReference, DataReferenceMulti].freeze
    end
  end
end
