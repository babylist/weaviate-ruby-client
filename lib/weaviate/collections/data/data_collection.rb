# frozen_string_literal: true

require_relative "../batch/batch_wrappers"

module Weaviate
  module Collections
    module Data
      # Port of weaviate.collections.data (_DataCollectionExecutor, sync): `collection.data`.
      class DataCollection
        H = ::Weaviate::Collections::Batch::Helpers
        private_constant :H

        attr_reader :name

        def initialize(connection:, name:, consistency_level: nil, tenant: nil, validate_arguments: true)
          @connection = connection
          @name = name
          @consistency_level = consistency_level
          @tenant = tenant
          @validate_arguments = validate_arguments
          @batch_grpc = ::Weaviate::Collections::Batch::BatchGRPC.for_connection(connection, consistency_level)
          @batch_rest = ::Weaviate::Collections::Batch::BatchREST.new(consistency_level)
          @batch_delete = ::Weaviate::Collections::Batch::BatchDeleteGRPC.new(
            weaviate_version: connection.weaviate_version, consistency_level: consistency_level
          )
        end

        # Insert a single object into the collection. `properties` may be given positionally or as a keyword.
        # Returns the UUID of the inserted object.
        #
        # Raises UnexpectedStatusCodeError if the insert fails, e.g. the given UUID already exists.
        def insert(properties_ = nil, properties: nil, references: nil, uuid: nil, vector: nil)
          properties = H.positional_or_keyword(properties_, properties, "properties", required: false)
          if @validate_arguments
            H.validate_input(
              [[String, nil], "uuid", uuid],
              [[Hash], "properties", properties],
              [[Hash, nil], "references", references]
            )
          end
          props = properties.nil? ? {} : serialize_props(properties)
          refs = references.nil? ? {} : serialize_refs(references)
          weaviate_obj = {
            "class" => @name,
            "properties" => props.merge(refs),
            "id" => (uuid.nil? ? ::Weaviate::Util.generate_uuid4 : uuid).to_s
          }
          weaviate_obj = parse_vector(weaviate_obj, vector) unless vector.nil?

          params, weaviate_obj = apply_context_to_params_and_object({}, weaviate_obj)
          @connection.post("/objects", weaviate_object: weaviate_obj, params: params,
                                       error_msg: "Object was not added",
                                       status_codes: codes(200, "insert object"))
          ::Weaviate::Util.get_valid_uuid(weaviate_obj["id"])
        end

        # Insert multiple objects (Hashes of properties or Weaviate::Classes::Data::DataObject) in one gRPC
        # request. Returns a Weaviate::Outputs::Batch::BatchObjectReturn.
        #
        # Raises WeaviateInsertManyAllFailedError if every object fails.
        def insert_many(objects)
          objs = objects.each_with_index.map do |obj, idx|
            if obj.is_a?(::Weaviate::Classes::Data::DataObject)
              ::Weaviate::Classes::Batch::BatchObjectInternal.new(
                collection: @name, vector: obj.vector,
                uuid: (obj.uuid.nil? ? ::Weaviate::Util.generate_uuid4 : obj.uuid).to_s,
                properties: obj.properties, tenant: @tenant, references: obj.references, index: idx
              )
            else
              ::Weaviate::Classes::Batch::BatchObjectInternal.new(
                collection: @name, vector: nil, uuid: ::Weaviate::Util.generate_uuid4, properties: obj,
                tenant: @tenant, references: nil, index: idx
              )
            end
          end

          res = @batch_grpc.objects(@connection, objects: objs, timeout: @connection.timeout_config.insert,
                                                 max_retries: 2)
          unless res.errors.empty?
            ::Weaviate::Collections::Batch.logger.error(
              { "message" => "Failed to send #{res.errors.length} objects in a batch of #{objs.length}. Please inspect " \
                             "the errors variable of the returned object for more information.",
                "errors" => res.errors }
            )
          end
          res
        end

        # Check for existence of a single object in the collection.
        def exists(uuid)
          H.validate_input([[String], "uuid", uuid])
          res = @connection.head("/objects/#{@name}/#{uuid}", params: apply_context({}),
                                                               error_msg: "object existence",
                                                               status_codes: codes([204, 404], "object existence"))
          res.status_code == 204
        end
        alias exists? exists

        # Replace an object in the collection (PUT).
        def replace(uuid_ = nil, uuid: nil, properties: nil, references: nil, vector: nil)
          uuid = H.positional_or_keyword(uuid_, uuid, "uuid")
          if @validate_arguments
            H.validate_input(
              [[String], "uuid", uuid],
              [[Hash], "properties", properties],
              [[Hash, nil], "references", references]
            )
          end
          props = properties.nil? ? {} : serialize_props(properties)
          refs = references.nil? ? {} : serialize_refs(references)
          weaviate_obj = { "class" => @name, "properties" => props.merge(refs) }
          weaviate_obj = parse_vector(weaviate_obj, vector) unless vector.nil?

          params, weaviate_obj = apply_context_to_params_and_object({}, weaviate_obj)
          weaviate_obj["id"] = uuid.to_s # must add ID to payload for PUT request
          @connection.put("/objects/#{@name}/#{uuid}", weaviate_object: weaviate_obj, params: params,
                                                        error_msg: "Object was not replaced.",
                                                        status_codes: codes(200, "replace object"))
          nil
        end

        # Update an object in the collection (PATCH).
        def update(uuid_ = nil, uuid: nil, properties: nil, references: nil, vector: nil)
          uuid = H.positional_or_keyword(uuid_, uuid, "uuid")
          if @validate_arguments
            H.validate_input(
              [[String], "uuid", uuid],
              [[Hash, nil], "properties", properties],
              [[Hash, nil], "references", references]
            )
          end
          props = properties.nil? ? {} : serialize_props(properties)
          refs = references.nil? ? {} : serialize_refs(references)
          weaviate_obj = { "class" => @name, "properties" => props.merge(refs) }
          weaviate_obj = parse_vector(weaviate_obj, vector) unless vector.nil?

          params, weaviate_obj = apply_context_to_params_and_object({}, weaviate_obj)
          @connection.patch("/objects/#{@name}/#{uuid}", weaviate_object: weaviate_obj, params: params,
                                                          error_msg: "Object was not updated.",
                                                          status_codes: codes([200, 204], "update object"))
          nil
        end

        # Create a reference between an object in this collection and any other object in Weaviate.
        # `to` is a UUID String or a ReferenceToMulti pointing to a single object.
        def reference_add(from_uuid_ = nil, from_property:, to:, from_uuid: nil)
          from_uuid = H.positional_or_keyword(from_uuid_, from_uuid, "from_uuid")
          validate_reference_args(from_uuid, from_property, to) if @validate_arguments
          ref_uuids, target = reference_parts(to)
          if one_to_many?(ref_uuids)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "reference_add does not support adding multiple objects to a reference at once. Use " \
                  "reference_add_many or reference_replace instead."
          end
          path = "/objects/#{@name}/#{from_uuid}/references/#{from_property}"
          ::Weaviate::Util.to_beacons(ref_uuids, target).each do |beacon|
            @connection.post(path, weaviate_object: beacon, params: apply_context({}),
                                   error_msg: "Reference was not added.",
                                   status_codes: codes(200, "add reference to object"))
          end
          nil
        end

        # Create multiple references in one batch (DataReference / DataReferenceMulti objects).
        # Returns a Weaviate::Outputs::Batch::BatchReferenceReturn.
        def reference_add_many(refs)
          batch = []
          refs.each_with_index do |ref, idx|
            ref.to_beacons.each do |beacon|
              batch << ::Weaviate::Classes::Batch::BatchReferenceInternal.new(
                from_: "#{::Weaviate::Classes::Data::BEACON}#{@name}/#{ref.from_uuid}/#{ref.from_property}",
                to: beacon,
                tenant: @tenant,
                from_uuid: ref.from_uuid.to_s,
                to_uuid: nil, # not relevant here, this entry is only needed for the batch module
                index: idx
              )
            end
          end
          @batch_rest.references(@connection, references: batch)
        end

        # Delete a reference from an object within the collection.
        def reference_delete(from_uuid_ = nil, from_property:, to:, from_uuid: nil)
          from_uuid = H.positional_or_keyword(from_uuid_, from_uuid, "from_uuid")
          validate_reference_args(from_uuid, from_property, to) if @validate_arguments
          ref_uuids, target = reference_parts(to)
          if one_to_many?(ref_uuids)
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "reference_delete does not support deleting multiple objects from a reference at once. Use " \
                  "reference_replace instead."
          end
          path = "/objects/#{@name}/#{from_uuid}/references/#{from_property}"
          ::Weaviate::Util.to_beacons(ref_uuids, target).each do |beacon|
            @connection.delete(path, weaviate_object: beacon, params: apply_context({}),
                                     error_msg: "Reference was not deleted.",
                                     status_codes: codes(204, "delete reference from object"))
          end
          nil
        end

        # Replace a reference of an object within the collection. `to` may be a UUID, a list of UUIDs or a
        # ReferenceToMulti.
        def reference_replace(from_uuid_ = nil, from_property:, to:, from_uuid: nil)
          from_uuid = H.positional_or_keyword(from_uuid_, from_uuid, "from_uuid")
          if @validate_arguments
            H.validate_input(
              [[String], "from_uuid", from_uuid],
              [[String], "from_property", from_property],
              [[String, multi_ref_predicate, [:list_of, String]], "references", to]
            )
          end
          ref_uuids, target = reference_parts(to)
          @connection.put("/objects/#{@name}/#{from_uuid}/references/#{from_property}",
                          weaviate_object: ::Weaviate::Util.to_beacons(ref_uuids, target),
                          params: apply_context({}),
                          error_msg: "Reference was not replaced.",
                          status_codes: codes(200, "replace reference on object"))
          nil
        end

        # Delete an object from the collection based on its UUID. Returns true if it was deleted.
        def delete_by_id(uuid)
          res = @connection.delete("/objects/#{@name}/#{uuid}", params: apply_context({}),
                                                                 error_msg: "Object could not be deleted.",
                                                                 status_codes: codes([204, 404], "delete object"))
          res.status_code == 204
        end

        # Delete multiple objects from the collection based on a filter (Weaviate::Classes::Query::Filter).
        # With `verbose: true` the deleted objects are returned; with `dry_run: true` nothing is deleted.
        # Returns a Weaviate::Outputs::Data::DeleteManyReturn.
        def delete_many(where_ = nil, where: nil, verbose: false, dry_run: false)
          where = H.positional_or_keyword(where_, where, "where")
          @batch_delete.batch_delete(@connection, name: @name, filters: where, verbose: verbose, dry_run: dry_run,
                                                  tenant: @tenant)
        end

        # Ingest multiple objects into the collection using server-side batching (Weaviate >= 1.36): the batch
        # sizes are handled by Weaviate. Accepts any Enumerable of property Hashes / DataObjects.
        # Returns a Weaviate::Outputs::Batch::BatchObjectReturn.
        def ingest(objs)
          results = ::Weaviate::Collections::Batch::BatchDataWrapper.new
          ctx = ::Weaviate::Collections::Batch::ContextManagerSync.new(
            ::Weaviate::Collections::Batch::BatchCollectionSync.new(
              connection: @connection, results: results, consistency_level: @consistency_level, name: @name,
              tenant: @tenant
            )
          )
          ctx.use do |batch|
            objs.each do |obj|
              if obj.is_a?(::Weaviate::Classes::Data::DataObject)
                batch.add_object(properties: obj.properties, references: obj.references, uuid: obj.uuid,
                                 vector: obj.vector)
              else
                batch.add_object(properties: obj, references: nil, uuid: nil, vector: nil)
              end
            end
          end
          results.results.objs
        end

        private

        def codes(ok, error) = ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)

        def multi_ref_predicate = ->(v) { H.reference_to_multi?(v) }

        def validate_reference_args(from_uuid, from_property, to)
          H.validate_input(
            [[String], "from_uuid", from_uuid],
            [[String], "from_property", from_property],
            [[String, multi_ref_predicate], "references", to]
          )
        end

        # => [uuids, target_collection]
        def reference_parts(to)
          H.reference_to_multi?(to) ? [to.uuids, to.target_collection.to_s] : [to, ""]
        end

        def one_to_many?(uuids) = uuids.is_a?(Array) && uuids.length > 1

        def apply_context(params)
          params["tenant"] = @tenant unless @tenant.nil?
          params["consistency_level"] = @consistency_level.to_s unless @consistency_level.nil?
          params
        end

        def apply_context_to_params_and_object(params, obj)
          obj["tenant"] = @tenant unless @tenant.nil?
          params["consistency_level"] = @consistency_level.to_s unless @consistency_level.nil?
          [params, obj]
        end

        def serialize_props(props)
          props.to_h { |key, val| [key.to_s, serialize_primitive(val)] }
        end

        def serialize_refs(refs)
          refs.to_h do |key, val|
            beacons =
              if H.reference_to_multi?(val)
                ::Weaviate::Util.to_beacons(val.uuids, val.target_collection.to_s)
              else
                ::Weaviate::Util.to_beacons(val, "")
              end
            [key.to_s, beacons]
          end
        end

        def serialize_primitive(value)
          case value
          when String, Integer, Float, true, false, nil then value
          when Symbol then value.to_s
          when Time, DateTime then ::Weaviate::Util.datetime_to_string(value)
          when ::Weaviate::Classes::Data::GeoCoordinate, ::Weaviate::Classes::Data::PhoneNumber then value.to_dict
          when ::Weaviate::Classes::Data::PhoneNumberType
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Cannot use _PhoneNumber when inserting a phone number. Use PhoneNumber instead."
          when Hash then value.to_h { |key, val| [key.to_s, serialize_primitive(val)] }
          when Array then value.map { |val| serialize_primitive(val) }
          else
            raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                  "Cannot serialize value of type #{value.class} to Weaviate."
          end
        end

        def parse_vector(obj, vector)
          if vector.is_a?(Hash)
            obj["vectors"] = vector.to_h { |key, val| [key.to_s, H.get_vector_v4(val)] }
          else
            obj["vector"] = H.get_vector_v4(vector)
          end
          obj
        end
      end
    end
  end
end
