# frozen_string_literal: true

require "google/protobuf/well_known_types"
require_relative "helpers"

module Weaviate
  module Collections
    module Batch
      # Port of weaviate.collections.batch.grpc_batch._BatchGRPC: inserts multiple objects into Weaviate
      # through the gRPC API. Used by `collection.data` and the batching classes.
      class BatchGRPC
        attr_reader :grpc_max_msg_size, :consistency_level

        def initialize(weaviate_version:, consistency_level:, grpc_max_msg_size:)
          @weaviate_version = weaviate_version
          @consistency_level = Helpers.consistency_level_to_grpc(consistency_level)
          @grpc_max_msg_size = grpc_max_msg_size || ::Weaviate::Connect::MAX_GRPC_MESSAGE_LENGTH
        end

        def self.for_connection(connection, consistency_level)
          new(weaviate_version: connection.weaviate_version, consistency_level: consistency_level,
              grpc_max_msg_size: connection.grpc_max_msg_size)
        end

        def grpc_object(obj)
          ::Weaviate::V1::BatchObject.new(
            collection: obj.collection,
            uuid: obj.uuid.nil? ? ::Weaviate::Util.generate_uuid4 : obj.uuid.to_s,
            properties: (translate_properties(obj.properties, obj.references || {}) unless obj.properties.nil?),
            tenant: obj.tenant,
            vector_bytes: single_vec(obj.vector),
            vectors: multi_vec(obj.vector) || []
          )
        end

        def grpc_objects(objects) = objects.map { |obj| grpc_object(obj) }

        def grpc_reference(reference)
          ref = ::Weaviate::Classes::Batch::BatchReference.from_internal(reference)
          ::Weaviate::V1::BatchReference.new(
            name: ref.from_property_name,
            from_collection: ref.from_object_collection,
            from_uuid: ref.from_object_uuid.to_s,
            to_collection: ref.to_object_collection,
            to_uuid: ref.to_object_uuid.to_s,
            tenant: ref.tenant
          )
        end

        def grpc_references(references) = references.map { |ref| grpc_reference(ref) }

        # Insert multiple objects (BatchObjectInternal) into Weaviate through the gRPC API.
        # Returns a Weaviate::Outputs::Batch::BatchObjectReturn.
        def objects(connection, objects:, timeout:, max_retries:)
          weaviate_objs = grpc_objects(objects)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          request = ::Weaviate::V1::BatchObjectsRequest.new(objects: weaviate_objs,
                                                             consistency_level: @consistency_level)
          errors = connection.grpc_batch_objects(request, timeout: timeout, max_retries: max_retries)

          if errors.length == weaviate_objs.length
            raise ::Weaviate::Exceptions::WeaviateInsertManyAllFailedError,
                  "Here is the set of all errors: #{errors.values.uniq.join("\n")}"
          end

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          all_responses = Array.new(weaviate_objs.length)
          return_success = {}
          return_errors = {}
          weaviate_objs.each_with_index do |weav_obj, idx|
            obj = objects[idx]
            if errors.key?(idx)
              error = ::Weaviate::Outputs::Batch::ErrorObject.new(
                message: errors[idx],
                object_: ::Weaviate::Classes::Batch::BatchObject.from_internal(obj),
                original_uuid: obj.uuid
              )
              return_errors[obj.index] = error
              all_responses[idx] = error
            else
              success = ::Weaviate::Util.get_valid_uuid(weav_obj.uuid)
              return_success[obj.index] = success
              all_responses[idx] = success
            end
          end

          ::Weaviate::Outputs::Batch::BatchObjectReturn.new(
            uuids: return_success, errors: return_errors, has_errors: !errors.empty?,
            _all_responses: all_responses, elapsed_seconds: elapsed
          )
        end

        # Start a new stream for send/recv messages about the ongoing server-side batching. +requests+ is an
        # Enumerable of BatchStreamRequest; yields each BatchStreamReply.
        def stream(connection, requests:, &block)
          connection.grpc_batch_stream(requests, &block)
        end

        def self.validate_props(props, nested: false)
          raise ::Weaviate::Exceptions::WeaviateInsertInvalidPropertyError, props if !nested && key?(props, "id")
          raise ::Weaviate::Exceptions::WeaviateInsertInvalidPropertyError, props if key?(props, "vector")
        end

        def self.key?(props, name) = props.key?(name) || props.key?(name.to_sym)

        def self.serialize_primitive(value)
          return ::Weaviate::Util.datetime_to_string(value) if Helpers.datetime?(value)
          return value.map { |val| serialize_primitive(val) } if value.is_a?(Array)
          return value.to_s if value.is_a?(Symbol)

          value
        end

        private

        def single_vec(vectors)
          return nil unless Helpers.is_1d_vector(vectors)

          Helpers.pack_single(vectors)
        end

        def multi_vec(vectors)
          return nil if vectors.nil? || Helpers.is_1d_vector(vectors)
          unless vectors.is_a?(Hash)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid vectors: #{vectors.inspect}"
          end

          vectors.map do |name, vec_or_vecs|
            bytes, type = Helpers.parse_single_or_multi_vec(vec_or_vecs)
            ::Weaviate::V1::Vectors.new(name: name.to_s, vector_bytes: bytes, type: type)
          end
        end

        def translate_properties(data, refs, nested: false)
          self.class.validate_props(data, nested: nested)

          multi_target = []
          single_target = []
          non_ref_properties = {}
          bool_arrays = []
          text_arrays = []
          int_arrays = []
          float_arrays = []
          object_properties = []
          object_array_properties = []
          empty_lists = []

          refs.each do |key, ref|
            key = key.to_s
            if Helpers.reference_to_multi?(ref)
              multi_target << ::Weaviate::V1::BatchObject::MultiTargetRefProps.new(
                uuids: Helpers.reference_uuids_str(ref), target_collection: ref.target_collection, prop_name: key
              )
            elsif ref.is_a?(String)
              single_target << ::Weaviate::V1::BatchObject::SingleTargetRefProps.new(uuids: [ref], prop_name: key)
            elsif ref.is_a?(Array)
              single_target << ::Weaviate::V1::BatchObject::SingleTargetRefProps.new(uuids: ref.map(&:to_s),
                                                                                     prop_name: key)
            else
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError, "Invalid reference: #{ref.inspect}"
            end
          end

          data.each do |key, entry|
            key = key.to_s
            if entry.is_a?(Hash)
              object_properties << ::Weaviate::V1::ObjectProperties.new(prop_name: key, value: nested_value(entry))
            elsif entry.is_a?(Array) && entry.empty?
              empty_lists << key
            elsif entry.is_a?(Array) && entry[0].is_a?(Hash)
              object_array_properties << ::Weaviate::V1::ObjectArrayProperties.new(
                values: entry.map { |v| nested_value(v) }, prop_name: key
              )
            elsif entry.is_a?(Array) && [true, false].include?(entry[0])
              bool_arrays << ::Weaviate::V1::BooleanArrayProperties.new(prop_name: key, values: entry)
            elsif entry.is_a?(Array) && entry[0].is_a?(String)
              text_arrays << ::Weaviate::V1::TextArrayProperties.new(prop_name: key, values: entry)
            elsif entry.is_a?(Array) && Helpers.datetime?(entry[0])
              text_arrays << ::Weaviate::V1::TextArrayProperties.new(
                prop_name: key, values: entry.map { |x| ::Weaviate::Util.datetime_to_string(x) }
              )
            elsif entry.is_a?(Array) && entry[0].is_a?(Integer)
              int_arrays << ::Weaviate::V1::IntArrayProperties.new(prop_name: key, values: entry)
            elsif entry.is_a?(Array) && entry[0].is_a?(Float)
              float_arrays << ::Weaviate::V1::NumberArrayProperties.new(prop_name: key, values_bytes: entry.pack("E*"))
            elsif entry.is_a?(::Weaviate::Classes::Data::GeoCoordinate) || entry.is_a?(::Weaviate::Classes::Data::PhoneNumber)
              non_ref_properties[key] = entry.to_dict
            else
              non_ref_properties[key] = self.class.serialize_primitive(entry)
            end
          end

          ::Weaviate::V1::BatchObject::Properties.new(
            non_ref_properties: ::Google::Protobuf::Struct.from_hash(non_ref_properties),
            multi_target_ref_props: multi_target,
            single_target_ref_props: single_target,
            text_array_properties: text_arrays,
            number_array_properties: float_arrays,
            int_array_properties: int_arrays,
            boolean_array_properties: bool_arrays,
            object_properties: object_properties,
            object_array_properties: object_array_properties,
            empty_list_props: empty_lists
          )
        end

        def nested_value(entry)
          parsed = translate_properties(entry, {}, nested: true)
          ::Weaviate::V1::ObjectPropertiesValue.new(
            non_ref_properties: parsed.non_ref_properties,
            int_array_properties: parsed.int_array_properties.to_a,
            text_array_properties: parsed.text_array_properties.to_a,
            number_array_properties: parsed.number_array_properties.to_a,
            boolean_array_properties: parsed.boolean_array_properties.to_a,
            object_properties: parsed.object_properties.to_a,
            object_array_properties: parsed.object_array_properties.to_a,
            empty_list_props: parsed.empty_list_props.to_a
          )
        end
      end
    end
  end
end
