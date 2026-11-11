# frozen_string_literal: true

module Weaviate
  # Port of weaviate.groups (`client.groups`).
  module Groups
    # Port of weaviate.groups.base._BaseExecutor.
    class GroupsBase
      def initialize(connection)
        @connection = connection
      end

      private

      def get_roles_of_group(group_id, group_type, include_permissions)
        res = @connection.get(
          "/authz/groups/#{::Weaviate::Util.escape_string(group_id)}/roles/#{group_type}",
          params: { "includeFullRoles" => include_permissions },
          error_msg: "Could not get roles of group #{group_id}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Get roles of group")
        )
        models = ::Weaviate::RBAC::Models
        res.json.to_h do |role|
          [role["name"], include_permissions ? models::Role.from_weaviate_role(role) : models::RoleBase.new(name: role["name"])]
        end
      end

      def assign_roles_to_group(roles, group_id, group_type)
        @connection.post(
          "/authz/groups/#{::Weaviate::Util.escape_string(group_id)}/assign",
          weaviate_object: { "roles" => roles, "groupType" => group_type },
          error_msg: "Could not assign roles #{roles} to group #{group_id}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Assign group to roles")
        )
        nil
      end

      def revoke_roles_from_group(roles, group_id, group_type)
        @connection.post(
          "/authz/groups/#{::Weaviate::Util.escape_string(group_id)}/revoke",
          weaviate_object: { "roles" => roles, "groupType" => group_type },
          error_msg: "Could not revoke roles #{roles} from group #{group_id}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Revoke group from user")
        )
        nil
      end

      def get_known_group_names_of_type(group_type)
        res = @connection.get(
          "/authz/groups/#{group_type}",
          error_msg: "Could not get known groups for group type #{group_type}",
          status_codes: ::Weaviate::Connect::ExpectedStatusCodes.new(ok: [200], error: "Get known groups")
        )
        groups = res.json
        raise "Expected a list of group names" unless groups.is_a?(Array)

        groups
      end
    end

    # Port of weaviate.groups.sync._GroupsOIDC (`client.groups.oidc`).
    class GroupsOIDC < GroupsBase
      # Get the roles assigned to a group specific to the configured OIDC's dynamic auth functionality.
      # Returns a Hash of role name => Role (include_permissions: true) or RoleBase.
      def get_assigned_roles(group_id:, include_permissions: false)
        get_roles_of_group(group_id, ::Weaviate::Users::USER_TYPE_OIDC, include_permissions)
      end

      # Assign roles to a group.
      def assign_roles(group_id:, role_names:)
        assign_roles_to_group(role_names.is_a?(String) ? [role_names] : role_names, group_id,
                              ::Weaviate::Users::USER_TYPE_OIDC)
      end

      # Revoke roles from a group.
      def revoke_roles(group_id:, role_names:)
        revoke_roles_from_group(role_names.is_a?(String) ? [role_names] : role_names, group_id,
                                ::Weaviate::Users::USER_TYPE_OIDC)
      end

      # Get the known group names specific to the configured OIDC's dynamic auth functionality.
      def get_known_group_names
        get_known_group_names_of_type(::Weaviate::Users::USER_TYPE_OIDC)
      end
    end

    # Port of weaviate.groups.sync._Groups (`client.groups`).
    class Groups
      attr_reader :oidc

      def initialize(connection)
        @oidc = GroupsOIDC.new(connection)
      end
    end
  end
end
