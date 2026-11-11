# frozen_string_literal: true

require "json"
require_relative "models"

module Weaviate
  # Port of weaviate.rbac (`client.roles`).
  module RBAC
    # Port of weaviate.rbac.sync._Roles.
    class Roles
      def initialize(connection)
        @connection = connection
      end

      # Get all roles. Returns a Hash of role name => Role.
      def list_all
        res = @connection.get("/authz/roles", error_msg: "Could not get roles", status_codes: codes([200], "Get roles"))
        res.json.to_h { |role| [role["name"], Models::Role.from_weaviate_role(role)] }
      end

      # Deprecated: use `users.get_my_user` instead.
      def get_current_roles
        ::Weaviate::Warnings.emit("This method is deprecated and will be removed in Q4 25. Please use " \
                                  "`users.get_my_user()` instead.")
        res = @connection.get("/authz/users/own-roles", error_msg: "Could not get roles",
                                                        status_codes: codes([200], "Get own roles"))
        res.json.map { |role| Models::Role.from_weaviate_role(role) }
      end

      # Check if a role exists.
      def exists(role_name_ = nil, role_name: role_name_)
        res = @connection.get("/authz/roles/#{role_name}", error_msg: "Could not get role #{role_name}",
                                                           status_codes: codes([200, 404], "Get role"))
        res.status_code == 200
      end
      alias exists? exists

      # Get the permissions granted to this role. Returns a Role or nil if it does not exist.
      def get(role_name_ = nil, role_name: role_name_)
        res = @connection.get("/authz/roles/#{role_name}", error_msg: "Could not get role #{role_name}",
                                                           status_codes: codes([200, 404], "Get role"))
        return nil if res.status_code == 404

        Models::Role.from_weaviate_role(res.json)
      end

      # Create a new role. Returns the created Role.
      def create(role_name:, permissions:)
        perms = Models.flatten_permissions(permissions).flat_map(&:to_weaviate)
        role = { "name" => role_name, "permissions" => perms }
        @connection.post("/authz/roles", weaviate_object: role, error_msg: "Could not create role: #{JSON.generate(role)}",
                                         status_codes: codes([201], "Create role"))
        Models::Role.from_weaviate_role(role)
      end

      # Get the ids and user type of users that have been assigned this role.
      def get_user_assignments(role_name_ = nil, role_name: role_name_)
        res = @connection.get("/authz/roles/#{role_name}/user-assignments",
                              error_msg: "Could not get users of role #{role_name}",
                              status_codes: codes([200], "Get users of role"))
        res.json.map do |a|
          Models::UserAssignment.new(user_id: a["userId"], user_type: Models::UserTypes.from(a["userType"]))
        end
      end

      # Get the ids and group type of groups that have been assigned this role.
      def get_group_assignments(role_name_ = nil, role_name: role_name_)
        res = @connection.get("/authz/roles/#{role_name}/group-assignments",
                              error_msg: "Could not get groups of role #{role_name}",
                              status_codes: codes([200], "Get groups of role"))
        res.json.map do |a|
          Models::GroupAssignment.new(group_id: a["groupId"], group_type: Models::GroupTypes.from(a["groupType"]))
        end
      end

      # Deprecated: use `roles.get_user_assignments` instead.
      def get_assigned_user_ids(role_name_ = nil, role_name: role_name_)
        ::Weaviate::Warnings.emit("This method is deprecated and will be removed in Q4 25. Please use " \
                                  "`roles.get_user_assignments` instead.")
        res = @connection.get("/authz/roles/#{role_name}/users", error_msg: "Could not get users of role #{role_name}",
                                                                 status_codes: codes([200], "Get users of role"))
        res.json
      end

      # Delete a role.
      def delete(role_name_ = nil, role_name: role_name_)
        @connection.delete("/authz/roles/#{role_name}", error_msg: "Could not delete role #{role_name}",
                                                        status_codes: codes([204], "Delete role"))
        nil
      end

      # Add permissions to a role (upsert).
      def add_permissions(permissions:, role_name:)
        @connection.post(
          "/authz/roles/#{role_name}/add-permissions",
          weaviate_object: { "permissions" => Models.flatten_permissions(permissions).flat_map(&:to_weaviate) },
          error_msg: "Could not add permissions", status_codes: codes([200], "Add permissions")
        )
        nil
      end

      # Remove permissions from a role. If these are the only permissions of the role, the role is deleted.
      def remove_permissions(permissions:, role_name:)
        @connection.post(
          "/authz/roles/#{role_name}/remove-permissions",
          weaviate_object: { "permissions" => Models.flatten_permissions(permissions).flat_map(&:to_weaviate) },
          error_msg: "Could not remove permissions", status_codes: codes([200], "Remove permissions")
        )
        nil
      end

      # Check if a role has a specific set of permissions.
      def has_permissions(permissions:, role:) # rubocop:disable Naming/PredicatePrefix
        Models.flatten_permissions(permissions).flat_map(&:to_weaviate).all? do |weav_perm|
          has_permission(permission: weav_perm, role: role)
        end
      end
      alias has_permissions? has_permissions

      private

      def has_permission(permission:, role:) # rubocop:disable Naming/PredicatePrefix
        res = @connection.post("/authz/roles/#{role}/has-permission", weaviate_object: permission,
                                                                      error_msg: "Could not check permission",
                                                                      status_codes: codes([200, 404], "Check permission"))
        # 200 means the check ran, the body is the answer
        res.status_code == 200 && res.json == true
      end

      def codes(ok, error)
        ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)
      end
    end
  end
end
