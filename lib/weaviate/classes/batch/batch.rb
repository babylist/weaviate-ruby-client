# frozen_string_literal: true

module Weaviate
  module Classes
    # Port of weaviate.classes.batch / weaviate.collections.classes.batch (input side).
    module Batch
      BEACON = "weaviate://localhost/"

      # Raised by the batch models when validation fails (pydantic ValidationError); converted into
      # WeaviateBatchValidationError by the batching code.
      class ValidationError < ArgumentError; end

      # Use this class when defining a shard whose vector indexing process will be awaited for in a sync
      # blocking fashion.
      class Shard < ::Weaviate::Model
        attribute :collection
        attribute :tenant, default: nil
      end

      # Port of _BatchObject (internal, wire-ready representation).
      class BatchObjectInternal < ::Weaviate::Model
        attribute :collection
        attribute :vector
        attribute :uuid
        attribute :properties
        attribute :tenant
        attribute :references
        attribute :index
        attribute :retry_count, default: 0
      end

      # Port of _BatchReference (internal, wire-ready representation).
      class BatchReferenceInternal < ::Weaviate::Model
        attribute :from_
        attribute :to
        attribute :tenant
        attribute :from_uuid
        attribute :to_uuid
        attribute :index
      end

      # A Weaviate object to be added to the database. Validates the collection name and UUID and generates a
      # UUID if one is not provided.
      class BatchObject < ::Weaviate::Model
        attribute :collection
        attribute :properties, default: nil
        attribute :references, default: nil
        attribute :uuid, default: nil
        attribute :vector, default: nil
        attribute :tenant, default: nil
        attribute :index
        attribute :retry_count, default: 0

        def initialize(**data)
          v = data[:vector]
          unless v.nil?
            data[:vector] =
              if v.is_a?(Hash)
                v.to_h { |key, val| [key, ::Weaviate::Collections::Batch::Helpers.get_vector_v4(val)] }
              else
                ::Weaviate::Collections::Batch::Helpers.get_vector_v4(v)
              end
          end
          data[:uuid] = data[:uuid].nil? ? ::Weaviate::Util.generate_uuid4 : ::Weaviate::Util.get_valid_uuid(data[:uuid])
          super
        end

        def after_initialize
          unless collection.is_a?(String) && !collection.empty?
            raise ValidationError, "collection: String should have at least 1 character, got #{collection.inspect}"
          end
          raise ValidationError, "properties: Input should be a valid dictionary" unless properties.nil? || properties.is_a?(Hash)
          raise ValidationError, "references: Input should be a valid dictionary" unless references.nil? || references.is_a?(Hash)
          raise ValidationError, "tenant: Input should be a valid string" unless tenant.nil? || tenant.is_a?(String)
          raise ValidationError, "index: Input should be a valid integer" unless index.is_a?(Integer)

          self.collection = ::Weaviate::Util.capitalize_first_letter(collection)
        end

        def to_internal
          BatchObjectInternal.new(collection: collection, vector: vector, uuid: uuid.to_s, properties: properties,
                                  tenant: tenant, references: references, index: index)
        end

        def self.from_internal(obj)
          new(collection: obj.collection, vector: obj.vector, uuid: obj.uuid, properties: obj.properties,
              tenant: obj.tenant, references: obj.references, index: obj.index, retry_count: obj.retry_count)
        end
      end

      # A reference between two objects in Weaviate. Validates the collection names and UUIDs.
      class BatchReference < ::Weaviate::Model
        attribute :from_object_collection
        attribute :from_object_uuid
        attribute :from_property_name
        attribute :to_object_uuid
        attribute :to_object_collection, default: nil
        attribute :tenant, default: nil
        attribute :index

        def after_initialize
          unless from_object_collection.is_a?(String) && !from_object_collection.empty?
            raise ValidationError, "from_object_collection: String should have at least 1 character"
          end
          unless to_object_collection.nil?
            raise ValidationError, "to_object_collection must not be empty if provided" if to_object_collection.to_s.empty?

            self.to_object_collection = ::Weaviate::Util.capitalize_first_letter(to_object_collection)
          end
          self.from_object_collection = ::Weaviate::Util.capitalize_first_letter(from_object_collection)
          self.from_object_uuid = validate_uuid(:from_object_uuid, from_object_uuid)
          self.to_object_uuid = validate_uuid(:to_object_uuid, to_object_uuid)
          raise ValidationError, "from_property_name: Input should be a valid string" unless from_property_name.is_a?(String)
        end

        def to_internal
          to_collection = to_object_collection.nil? ? "" : "#{to_object_collection}/"
          BatchReferenceInternal.new(
            from_uuid: from_object_uuid.to_s,
            from_: "#{BEACON}#{from_object_collection}/#{from_object_uuid}/#{from_property_name}",
            to: "#{BEACON}#{to_collection}#{to_object_uuid}",
            to_uuid: to_object_uuid.to_s,
            tenant: tenant,
            index: index
          )
        end

        def self.from_internal(ref)
          from = ref.from_.split("weaviate://localhost/")[1].split("/")
          to = ref.to.split("weaviate://localhost/")[1].split("/")
          to_object_collection =
            case to.length
            when 2 then to[0]
            when 1 then nil
            else raise ArgumentError, "Invalid reference 'to' value in _BatchReference object #{ref.inspect}"
            end
          new(from_object_collection: from[0], from_object_uuid: ref.from_uuid, from_property_name: from[-1],
              to_object_uuid: ref.to_uuid.nil? ? to[-1] : ref.to_uuid, to_object_collection: to_object_collection,
              tenant: ref.tenant, index: ref.index)
        end

        # Python `_to_beacon`
        def to_beacon
          "#{BEACON}#{from_object_collection}/#{from_object_uuid}/#{from_property_name}"
        end

        private

        def validate_uuid(name, value)
          ::Weaviate::Util.get_valid_uuid(value)
        rescue ArgumentError, TypeError => e
          raise ValidationError, "#{name}: #{e.message}"
        end
      end
    end
  end
end
