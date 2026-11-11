# frozen_string_literal: true

require "time"

module Weaviate
  # Port of weaviate.debug (`client.debug`).
  module Debug
    # Port of weaviate.debug.types.DebugRESTObject.
    class DebugRESTObject < ::Weaviate::Model
      attribute :collection
      attribute :creation_time
      attribute :last_update_time
      attribute :properties
      attribute :tenant, default: nil
      attribute :uuid
      attribute :vector, default: nil
      attribute :vectors, default: nil

      # Build from the REST object JSON (pydantic aliases: class, creationTimeUnix, lastUpdateTimeUnix, id).
      def self.from_weaviate(data)
        new(
          collection: data.fetch("class"),
          creation_time: ::Weaviate::Debug.parse_datetime(data.fetch("creationTimeUnix")),
          last_update_time: ::Weaviate::Debug.parse_datetime(data.fetch("lastUpdateTimeUnix")),
          properties: data.fetch("properties"),
          tenant: data["tenant"],
          uuid: ::Weaviate::Util.get_valid_uuid(data.fetch("id")),
          vector: data["vector"],
          vectors: data["vectors"]
        )
      end
    end

    # pydantic datetime parsing: numbers are unix timestamps (seconds, or milliseconds when
    # larger than 2e10); strings are ISO 8601.
    def self.parse_datetime(value)
      case value
      when Time then value
      when Numeric
        value.abs > 2e10 ? Time.at(Rational(value.to_i, 1000)).utc : Time.at(value).utc
      when String
        value.match?(/\A-?\d+(\.\d+)?\z/) ? parse_datetime(value.include?(".") ? value.to_f : value.to_i) : Time.iso8601(value)
      else
        raise TypeError, "Cannot parse datetime from #{value.inspect}"
      end
    end

    # Port of weaviate.debug.sync._Debug.
    class Debug
      def initialize(connection)
        @connection = connection
      end

      # Use the REST API endpoint /objects/{className}/{id} to retrieve an object directly from the
      # database without search. Returns a DebugRESTObject or nil if not found.
      def get_object_over_rest(collection_ = nil, uuid_ = nil, collection: collection_, uuid: uuid_,
                               consistency_level: nil, node_name: nil, tenant: nil)
        path = "/objects/#{collection}/#{uuid}"
        params = {}
        params["consistency"] = consistency_level.to_s unless consistency_level.nil?
        params["node_name"] = node_name unless node_name.nil?
        params["tenant"] = tenant unless tenant.nil?

        res = @connection.get(
          path, params: params, error_msg: "Object was not retrieved",
                status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200, 404], error: "get object")
        )
        return nil if res.status_code == 404

        DebugRESTObject.from_weaviate(res.json)
      end
    end
  end
end
