# frozen_string_literal: true

module Weaviate
  # Port of weaviate.aliases
  module Aliases
    # Port of weaviate.aliases.alias.AliasReturn: an alias returned from Weaviate.
    class AliasReturn < ::Weaviate::Model
      attribute :alias
      attribute :collection
    end

    # Port of weaviate.aliases.sync._Alias (`client.alias`).
    class Alias
      def initialize(connection)
        @connection = connection
      end

      # Get all aliases, optionally only those pointing to +collection+.
      # Returns a Hash of alias name => AliasReturn.
      def list_all(collection: nil)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        error_msg = +"list all aliases"
        error_msg << " for collection #{collection}" unless collection.nil?

        res = @connection.get(
          "/aliases",
          params: collection ? { "class" => collection } : nil,
          error_msg: error_msg,
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: error_msg)
        )
        response_typed = ::Weaviate::Util.decode_json_response_dict(res, "list all aliases")
        aliases = response_typed["aliases"]
        raise "Expected 'aliases' in response" if aliases.nil?

        aliases.to_h { |a| [a["alias"], AliasReturn.new(alias: a["alias"], collection: a["class"])] }
      end

      # Get the given alias, or nil if it does not exist.
      def get(alias_name:)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        res = @connection.get(
          "/aliases/#{alias_name}",
          error_msg: "Could not get alias #{alias_name}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200, 404], error: "get alias")
        )
        return nil if res.status_code == 404

        response_typed = ::Weaviate::Util.decode_json_response_dict(res, "get alias")
        AliasReturn.new(alias: response_typed["alias"], collection: response_typed["class"])
      end

      # Create an alias for a given collection.
      def create(alias_name:, target_collection:)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        @connection.post(
          "/aliases",
          weaviate_object: { "class" => target_collection, "alias" => alias_name },
          error_msg: "Could not create alias #{alias_name} for collection #{target_collection}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "create aliases")
        )
        nil
      end

      # Delete an alias. Returns true if it was deleted, false if it did not exist.
      def delete(alias_name:)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        res = @connection.delete(
          "/aliases/#{alias_name}",
          error_msg: "Could not delete alias #{alias_name}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [204, 404], error: "delete aliases")
        )
        res.status_code == 204
      end

      # Point an existing alias at a new collection. Returns false if the alias does not exist.
      def update(alias_name:, new_target_collection:)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        res = @connection.put(
          "/aliases/#{alias_name}",
          weaviate_object: { "class" => new_target_collection },
          error_msg: "Could not update alias #{alias_name} to point to collection #{new_target_collection}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200, 404], error: "update aliases")
        )
        res.status_code == 200
      end

      # Check if an alias exists.
      def exists(alias_name:)
        @connection.weaviate_version.check_is_at_least_1_32_0("alias")

        res = @connection.get(
          "/aliases/#{alias_name}",
          error_msg: "Alias may not exist.",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200, 404], error: "alias exists")
        )
        res.status_code == 200
      end
      alias exists? exists
    end
  end
end
