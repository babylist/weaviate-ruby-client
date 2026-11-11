# frozen_string_literal: true

require_relative "models"

module Weaviate
  module Users
    # Port of weaviate.users.base._BaseExecutor.
    class UsersBase
      def initialize(connection)
        @connection = connection
      end

      private

      def models = ::Weaviate::RBAC::Models

      def codes(ok, error)
        ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)
      end

      def escape(value) = ::Weaviate::Util.escape_string(value)

      def as_list(role_names) = role_names.is_a?(String) ? [role_names] : role_names

      def get_roles_of_user(user_id, user_type, include_permissions)
        res = @connection.get("/authz/users/#{escape(user_id)}/roles/#{user_type}",
                              params: { "includeFullRoles" => include_permissions },
                              error_msg: "Could not get roles of user #{user_id}",
                              status_codes: codes([200], "Get roles of user"))
        res.json.to_h do |role|
          [role["name"],
           include_permissions ? models::Role.from_weaviate_role(role) : models::RoleBase.new(name: role["name"])]
        end
      end

      def get_roles_of_user_deprecated(user_id)
        res = @connection.get("/authz/users/#{escape(user_id)}/roles",
                              error_msg: "Could not get roles of user #{user_id}",
                              status_codes: codes([200], "Get roles of user"))
        res.json.to_h { |role| [role["name"], models::Role.from_weaviate_role(role)] }
      end

      def assign_roles_to_user(roles, user_id, user_type)
        payload = { "roles" => roles }
        payload["userType"] = user_type unless user_type.nil?
        @connection.post("/authz/users/#{escape(user_id)}/assign", weaviate_object: payload,
                                                                   error_msg: "Could not assign roles #{roles} to user #{user_id}",
                                                                   status_codes: codes([200], "Assign user to roles"))
        nil
      end

      def revoke_roles_from_user(roles, user_id, _user_type)
        # Mirrors the Python client, which only sends the role names here.
        @connection.post("/authz/users/#{escape(user_id)}/revoke", weaviate_object: { "roles" => roles },
                                                                   error_msg: "Could not revoke roles #{roles} from user #{user_id}",
                                                                   status_codes: codes([200], "Revoke roles from user"))
        nil
      end
    end

    # Port of weaviate.users.sync._UsersOIDC (`client.users.oidc`).
    class UsersOIDC < UsersBase
      # Get the roles assigned to a user specific to the configured OIDC's dynamic auth functionality.
      def get_assigned_roles(user_id:, include_permissions: false)
        get_roles_of_user(user_id, USER_TYPE_OIDC, include_permissions)
      end

      def assign_roles(user_id:, role_names:)
        assign_roles_to_user(as_list(role_names), user_id, USER_TYPE_OIDC)
      end

      def revoke_roles(user_id:, role_names:)
        revoke_roles_from_user(as_list(role_names), user_id, USER_TYPE_OIDC)
      end
    end

    # Port of weaviate.users.sync._UsersDB (`client.users.db`).
    class UsersDB < UsersBase
      # Get the roles assigned to a user.
      def get_assigned_roles(user_id:, include_permissions: false)
        get_roles_of_user(user_id, USER_TYPE_DB, include_permissions)
      end

      def assign_roles(user_id:, role_names:)
        assign_roles_to_user(as_list(role_names), user_id, USER_TYPE_DB)
      end

      def revoke_roles(user_id:, role_names:)
        revoke_roles_from_user(as_list(role_names), user_id, USER_TYPE_DB)
      end

      # Create a new db user and return its API key (which cannot be retrieved later).
      def create(user_id:)
        res = @connection.post("/users/db/#{user_id}", weaviate_object: {}, error_msg: "Could not create user '#{user_id}'",
                                                       status_codes: codes([201], "Create user"))
        ::Weaviate::Util.decode_json_response_dict(res, "Create user")["apikey"].to_s
      end

      # Delete a (dynamic) db user. Returns false if it did not exist.
      def delete(user_id:)
        res = @connection.delete("/users/db/#{user_id}", error_msg: "Could not delete user '#{user_id}'",
                                                         status_codes: codes([204, 404], "Delete user"))
        res.status_code == 204
      end

      # Rotate the key of a db user. Returns the new API key.
      def rotate_key(user_id:)
        res = @connection.post("/users/db/#{user_id}/rotate-key", weaviate_object: {},
                                                                  error_msg: "Could not rotate key for user '#{user_id}'",
                                                                  status_codes: codes([200], "Rotate key"))
        ::Weaviate::Util.decode_json_response_dict(res, "Rotate key")["apikey"].to_s
      end

      # Activate a deactivated user. Returns false if it was already active.
      def activate(user_id:)
        res = @connection.post("/users/db/#{user_id}/activate", weaviate_object: {},
                                                                error_msg: "Could not activate user '#{user_id}'",
                                                                status_codes: codes([200, 409], "Activate user"))
        res.status_code == 200
      end

      # Deactivate an active user. With +revoke_key+ the old key is revoked and must be rotated.
      def deactivate(user_id:, revoke_key: false)
        res = @connection.post("/users/db/#{user_id}/deactivate", weaviate_object: { "revoke_key" => revoke_key },
                                                                  error_msg: "Could not deactivate user '#{user_id}'",
                                                                  status_codes: codes([200, 409], "Deactivate user"))
        res.status_code == 200
      end

      # Get all information about a user, or nil if it does not exist.
      def get(user_id:, include_last_used_time: false)
        res = @connection.get("/users/db/#{user_id}", params: { "includeLastUsedTime" => include_last_used_time },
                                                      error_msg: "Could not get user '#{user_id}'",
                                                      status_codes: codes([200, 404], "get user"))
        return nil if res.status_code == 404

        ::Weaviate::Users.user_db_from_weaviate(::Weaviate::Util.decode_json_response_dict(res, "Get user"))
      end

      # List all DB users.
      def list_all(include_last_used_time: false)
        res = @connection.get("/users/db", params: { "includeLastUsedTime" => include_last_used_time },
                                           error_msg: "Could not list all users",
                                           status_codes: codes([200], "list all users"))
        ::Weaviate::Util.decode_json_response_list(res, "Get user").map { |u| ::Weaviate::Users.user_db_from_weaviate(u) }
      end
    end

    # Port of weaviate.users.sync._Users (`client.users`).
    class Users < UsersBase
      attr_reader :db, :oidc

      def initialize(connection)
        super
        @db = UsersDB.new(connection)
        @oidc = UsersOIDC.new(connection)
      end

      # Get the currently authenticated user. Returns an OwnUser.
      def get_my_user
        res = @connection.get("/users/own-info", error_msg: "Could not get roles",
                                                 status_codes: codes([200], "Get own roles"))
        parsed = ::Weaviate::Util.decode_json_response_dict(res, "Get current user")
        # The API returns "username" for 1.29 instead of "user_id"
        user_id = parsed.key?("username") ? parsed["username"] : parsed["user_id"]
        OwnUser.new(
          user_id: user_id,
          roles: parsed["roles"].nil? ? {} : parsed["roles"].to_h { |r| [r["name"], models::Role.from_weaviate_role(r)] },
          groups: parsed.fetch("groups", [])
        )
      end

      # Deprecated: use `users.db.get_assigned_roles` and/or `users.oidc.get_assigned_roles` instead.
      def get_assigned_roles(user_id_ = nil, user_id: user_id_)
        deprecated("users.db.get_assigned_roles` and/or `users.oidc.get_assigned_roles")
        get_roles_of_user_deprecated(user_id)
      end

      # Deprecated: use `users.db.assign_roles` and/or `users.oidc.assign_roles` instead.
      def assign_roles(user_id:, role_names:)
        deprecated("users.db.assign_roles` and/or `users.oidc.assign_roles")
        assign_roles_to_user(as_list(role_names), user_id, nil)
      end

      # Deprecated: use `users.db.revoke_roles` and/or `users.oidc.revoke_roles` instead.
      def revoke_roles(user_id:, role_names:)
        deprecated("users.db.revoke_roles` and/or `users.oidc.revoke_roles")
        revoke_roles_from_user(as_list(role_names), user_id, nil)
      end

      private

      def deprecated(replacement)
        ::Weaviate::Warnings.emit("This method is deprecated and will be removed in Q4 25. Please use " \
                                  "`#{replacement}` instead.")
      end
    end
  end
end
