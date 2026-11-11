# frozen_string_literal: true

require "set"

module Weaviate
  module RBAC
    # Port of weaviate.rbac.models.
    module Models
      module UserTypes
        extend ::Weaviate::StrEnum
        DB_DYNAMIC = "db_user"
        DB_STATIC = "db_env_user"
        OIDC = "oidc"
      end

      module GroupTypes
        extend ::Weaviate::StrEnum
        OIDC = "oidc"
      end

      # Scope of the role permission.
      module RoleScope
        extend ::Weaviate::StrEnum
        MATCH = "match"
        ALL = "all"
      end

      class UserAssignment < ::Weaviate::Model
        attribute :user_id
        attribute :user_type
      end

      class GroupAssignment < ::Weaviate::Model
        attribute :group_id
        attribute :group_type
      end

      # --- Actions ---

      module AliasAction
        extend ::Weaviate::StrEnum
        CREATE = "create_aliases"
        READ = "read_aliases"
        UPDATE = "update_aliases"
        DELETE = "delete_aliases"
      end

      module CollectionsAction
        extend ::Weaviate::StrEnum
        CREATE = "create_collections"
        READ = "read_collections"
        UPDATE = "update_collections"
        DELETE = "delete_collections"
        MANAGE = "manage_collections"
      end

      module TenantsAction
        extend ::Weaviate::StrEnum
        CREATE = "create_tenants"
        READ = "read_tenants"
        UPDATE = "update_tenants"
        DELETE = "delete_tenants"
      end

      module DataAction
        extend ::Weaviate::StrEnum
        CREATE = "create_data"
        READ = "read_data"
        UPDATE = "update_data"
        DELETE = "delete_data"
        MANAGE = "manage_data"
      end

      module RolesAction
        extend ::Weaviate::StrEnum
        MANAGE = "manage_roles" # backward compatibility
        CREATE = "create_roles"
        READ = "read_roles"
        UPDATE = "update_roles"
        DELETE = "delete_roles"
      end

      module GroupAction
        extend ::Weaviate::StrEnum
        READ = "read_groups"
        ASSIGN_AND_REVOKE = "assign_and_revoke_groups"
      end

      module UsersAction
        extend ::Weaviate::StrEnum
        CREATE = "create_users"
        READ = "read_users"
        UPDATE = "update_users"
        DELETE = "delete_users"
        ASSIGN_AND_REVOKE = "assign_and_revoke_users"
      end

      module ClusterAction
        extend ::Weaviate::StrEnum
        READ = "read_cluster"
      end

      module NodesAction
        extend ::Weaviate::StrEnum
        READ = "read_nodes"
      end

      module BackupsAction
        extend ::Weaviate::StrEnum
        READ = "read_backups"
        MANAGE = "manage_backups"
      end

      module MCPAction
        extend ::Weaviate::StrEnum
        CREATE = "create_mcp"
        READ = "read_mcp"
        UPDATE = "update_mcp"
      end

      module ReplicateAction
        extend ::Weaviate::StrEnum
        CREATE = "create_replicate"
        READ = "read_replicate"
        UPDATE = "update_replicate"
        DELETE = "delete_replicate"
      end

      # --- Permissions ---

      # Port of _Permission: +actions+ is a Set of action Strings.
      class Permission < ::Weaviate::Model
        attribute :actions, default: -> { Set.new }

        # The action enum this permission accepts (overridden by subclasses).
        def self.action_enum = nil

        def after_initialize
          self.actions = Set.new(actions)
          enum = self.class.action_enum
          actions.each { |a| enum.from(a) } if enum
        end

        # Port of _to_weaviate: the REST shapes of this permission (one per action).
        def to_weaviate
          raise NotImplementedError
        end

        # Resource identity used to merge permissions (every attribute but +actions+).
        def resource_key
          (self.class.attribute_names - [:actions]).map { |f| "#{f}#{public_send(f)}#" }.join
        end
      end

      class CollectionsPermission < Permission
        attribute :collection
        def self.action_enum = CollectionsAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "collections" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection) } }
          end
        end
      end

      class TenantsPermission < Permission
        attribute :collection
        attribute :tenant
        def self.action_enum = TenantsAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "tenants" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection), "tenant" => tenant } }
          end
        end
      end

      class NodesPermission < Permission
        attribute :verbosity
        attribute :collection
        def self.action_enum = NodesAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "nodes" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection),
                           "verbosity" => verbosity } }
          end
        end
      end

      class ReplicatePermission < Permission
        attribute :collection
        attribute :shard
        def self.action_enum = ReplicateAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "replicate" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection), "shard" => shard } }
          end
        end
      end

      class RolesPermission < Permission
        attribute :role
        attribute :scope, default: nil
        def self.action_enum = RolesAction

        def to_weaviate
          roles = { "role" => role }
          roles["scope"] = scope unless scope.nil?
          actions.map { |action| { "action" => action, "roles" => roles } }
        end
      end

      class UsersPermission < Permission
        attribute :users
        def self.action_enum = UsersAction

        def to_weaviate
          actions.map { |action| { "action" => action, "users" => { "users" => users } } }
        end
      end

      class AliasPermission < Permission
        attribute :alias
        attribute :collection
        def self.action_enum = AliasAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "aliases" => { "alias" => ::Weaviate::Util.capitalize_first_letter(self.alias),
                             "collection" => collection } }
          end
        end
      end

      class GroupsPermission < Permission
        attribute :group
        attribute :group_type
        def self.action_enum = GroupAction

        def to_weaviate
          actions.map { |action| { "action" => action, "groups" => { "group" => group, "groupType" => group_type } } }
        end
      end

      class BackupsPermission < Permission
        attribute :collection
        def self.action_enum = BackupsAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "backups" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection) } }
          end
        end
      end

      class MCPPermission < Permission
        def self.action_enum = MCPAction

        def to_weaviate
          actions.map { |action| { "action" => action } }
        end
      end

      class ClusterPermission < Permission
        def self.action_enum = ClusterAction

        def to_weaviate
          actions.map { |action| { "action" => action } }
        end
      end

      class DataPermission < Permission
        attribute :collection
        attribute :tenant
        def self.action_enum = DataAction

        def to_weaviate
          actions.map do |action|
            { "action" => action,
              "data" => { "collection" => ::Weaviate::Util.capitalize_first_letter(collection), "tenant" => tenant } }
          end
        end
      end

      class CollectionsPermissionOutput < CollectionsPermission; end
      class DataPermissionOutput < DataPermission; end
      class ReplicatePermissionOutput < ReplicatePermission; end
      class RolesPermissionOutput < RolesPermission; end
      class UsersPermissionOutput < UsersPermission; end
      class GroupsPermissionOutput < GroupsPermission; end
      class AliasPermissionOutput < AliasPermission; end
      class ClusterPermissionOutput < ClusterPermission; end
      class BackupsPermissionOutput < BackupsPermission; end
      class MCPPermissionOutput < MCPPermission; end
      class NodesPermissionOutput < NodesPermission; end
      class TenantsPermissionOutput < TenantsPermission; end

      # Python `PermissionsOutputType` (a Union).
      PermissionsOutputType = [
        AliasPermissionOutput, ClusterPermissionOutput, CollectionsPermissionOutput, DataPermissionOutput,
        RolesPermissionOutput, UsersPermissionOutput, BackupsPermissionOutput, MCPPermissionOutput,
        NodesPermissionOutput, TenantsPermissionOutput, ReplicatePermissionOutput, GroupsPermissionOutput
      ].freeze

      class RoleBase < ::Weaviate::Model
        attribute :name
      end

      class Role < RoleBase
        PERMISSION_FIELDS = %i[
          alias_permissions cluster_permissions collections_permissions data_permissions roles_permissions
          users_permissions backups_permissions mcp_permissions nodes_permissions tenants_permissions
          replicate_permissions groups_permissions
        ].freeze
        PERMISSION_FIELDS.each { |f| attribute f, default: -> { [] } }

        # All permissions of this role, flattened.
        def permissions
          PERMISSION_FIELDS.flat_map { |f| public_send(f) }
        end

        # Port of Role._from_weaviate_role.
        def self.from_weaviate_role(role)
          perms = PERMISSION_FIELDS.to_h { |f| [f, []] }

          role["permissions"].each do |permission|
            action = permission["action"]
            if ClusterAction.include?(action)
              perms[:cluster_permissions] << ClusterPermissionOutput.new(actions: [action])
            elsif UsersAction.include?(action)
              users = permission["users"]
              perms[:users_permissions] << UsersPermissionOutput.new(actions: [action], users: users["users"]) unless users.nil?
            elsif CollectionsAction.include?(action)
              collections = permission["collections"]
              unless collections.nil?
                perms[:collections_permissions] <<
                  CollectionsPermissionOutput.new(collection: collections["collection"], actions: [action])
              end
            elsif TenantsAction.include?(action)
              tenants = permission["tenants"]
              unless tenants.nil?
                perms[:tenants_permissions] << TenantsPermissionOutput.new(
                  collection: tenants["collection"], tenant: tenants.fetch("tenant", "*"), actions: [action]
                )
              end
            elsif RolesAction.include?(action)
              roles = permission["roles"]
              unless roles.nil?
                scope = roles["scope"]
                perms[:roles_permissions] << RolesPermissionOutput.new(
                  role: roles["role"], actions: [action],
                  scope: scope.nil? || scope.empty? ? nil : RoleScope.from(scope)
                )
              end
            elsif DataAction.include?(action)
              data = permission["data"]
              unless data.nil?
                perms[:data_permissions] << DataPermissionOutput.new(
                  collection: data["collection"], tenant: data.fetch("tenant", "*"), actions: [action]
                )
              end
            elsif BackupsAction.include?(action)
              backups = permission["backups"]
              unless backups.nil?
                perms[:backups_permissions] <<
                  BackupsPermissionOutput.new(collection: backups["collection"], actions: [action])
              end
            elsif MCPAction.include?(action)
              perms[:mcp_permissions] << MCPPermissionOutput.new(actions: [action])
            elsif NodesAction.include?(action)
              nodes = permission["nodes"]
              unless nodes.nil?
                perms[:nodes_permissions] << NodesPermissionOutput.new(
                  collection: nodes.fetch("collection", "*"), verbosity: nodes["verbosity"], actions: [action]
                )
              end
            elsif ReplicateAction.include?(action)
              replicate = permission["replicate"]
              unless replicate.nil?
                perms[:replicate_permissions] << ReplicatePermissionOutput.new(
                  collection: replicate["collection"], shard: replicate.fetch("shard", "*"), actions: [action]
                )
              end
            elsif AliasAction.include?(action)
              aliases = permission["aliases"]
              unless aliases.nil?
                perms[:alias_permissions] << AliasPermissionOutput.new(
                  alias: aliases["alias"], collection: aliases["collection"], actions: [action]
                )
              end
            elsif GroupAction.include?(action)
              groups = permission["groups"]
              unless groups.nil?
                perms[:groups_permissions] << GroupsPermissionOutput.new(
                  group: groups["group"], group_type: groups["groupType"], actions: [action]
                )
              end
            else
              ::Weaviate::Warnings.unknown_permission_encountered(permission)
            end
          end

          new(name: role["name"], **perms.transform_values { |list| Models.join_permissions(list) })
        end
      end

      # Port of _join_permissions: permissions on the same resource are merged into
      # one permission carrying all actions.
      def self.join_permissions(permissions)
        unified = {}
        permissions.each do |perm|
          key = perm.resource_key
          if unified.key?(key)
            unified[key].actions.merge(perm.actions)
          else
            unified[key] = perm
          end
        end
        unified.values
      end

      # Port of _flatten_permissions: accepts a permission, an Array of permissions or
      # an Array mixing permissions and Arrays of permissions.
      def self.flatten_permissions(permissions)
        return [permissions] if permissions.is_a?(Permission)

        permissions.each_with_object([]) do |permission, out|
          if permission.is_a?(Permission)
            out << permission
          else
            out.concat(permission.to_a)
          end
        end
      end

      # Port of weaviate.rbac.models.Actions.
      module Actions
        Alias = AliasAction
        Data = DataAction
        Collections = CollectionsAction
        Roles = RolesAction
        Cluster = ClusterAction
        Nodes = NodesAction
        Backups = BackupsAction
        MCP = MCPAction
        Tenants = TenantsAction
        Users = UsersAction
        Replicate = ReplicateAction
        Groups = GroupAction
      end

      def self.as_list(value)
        value.is_a?(String) ? [value] : value.to_a
      end

      module GroupsPermissions
        module_function

        def oidc(group:, read: false, assign_and_revoke: false)
          Models.as_list(group).filter_map do |g|
            permission = GroupsPermission.new(group: g, group_type: "oidc", actions: [])
            permission.actions << GroupAction::READ if read
            permission.actions << GroupAction::ASSIGN_AND_REVOKE if assign_and_revoke
            permission unless permission.actions.empty?
          end
        end
      end

      module NodesPermissions
        module_function

        def verbose(collection:, read: false)
          Models.as_list(collection).filter_map do |c|
            permission = NodesPermission.new(collection: c, verbosity: "verbose", actions: [])
            permission.actions << NodesAction::READ if read
            permission unless permission.actions.empty?
          end
        end

        def minimal(read: false)
          return [] unless read

          [NodesPermission.new(collection: "*", verbosity: "minimal", actions: [NodesAction::READ])]
        end
      end

      # Port of weaviate.rbac.models.Permissions: builders returning Arrays of permissions.
      module Permissions
        Nodes = NodesPermissions
        Groups = GroupsPermissions

        module_function

        def alias(alias:, collection:, create: false, read: false, update: false, delete: false)
          aliases = Models.as_list(binding.local_variable_get(:alias))
          collections = Models.as_list(collection)
          aliases.flat_map do |a|
            collections.filter_map do |c|
              permission = AliasPermission.new(alias: a, collection: c, actions: [])
              permission.actions << AliasAction::CREATE if create
              permission.actions << AliasAction::READ if read
              permission.actions << AliasAction::UPDATE if update
              permission.actions << AliasAction::DELETE if delete
              permission unless permission.actions.empty?
            end
          end
        end

        def data(collection:, tenant: nil, create: false, read: false, update: false, delete: false)
          tenants = tenant.nil? ? ["*"] : Models.as_list(tenant)
          Models.as_list(collection).flat_map do |c|
            tenants.filter_map do |t|
              permission = DataPermission.new(collection: c, tenant: t, actions: [])
              permission.actions << DataAction::CREATE if create
              permission.actions << DataAction::READ if read
              permission.actions << DataAction::UPDATE if update
              permission.actions << DataAction::DELETE if delete
              permission unless permission.actions.empty?
            end
          end
        end

        def collections(collection:, create_collection: false, read_config: false, update_config: false,
                        delete_collection: false)
          Models.as_list(collection).filter_map do |c|
            permission = CollectionsPermission.new(collection: c, actions: [])
            permission.actions << CollectionsAction::CREATE if create_collection
            permission.actions << CollectionsAction::READ if read_config
            permission.actions << CollectionsAction::UPDATE if update_config
            permission.actions << CollectionsAction::DELETE if delete_collection
            permission unless permission.actions.empty?
          end
        end

        def tenants(collection:, tenant: nil, create: false, read: false, update: false, delete: false)
          tenants = tenant.nil? ? ["*"] : Models.as_list(tenant)
          Models.as_list(collection).flat_map do |c|
            tenants.filter_map do |t|
              permission = TenantsPermission.new(collection: c, tenant: t, actions: [])
              permission.actions << TenantsAction::CREATE if create
              permission.actions << TenantsAction::READ if read
              permission.actions << TenantsAction::UPDATE if update
              permission.actions << TenantsAction::DELETE if delete
              permission unless permission.actions.empty?
            end
          end
        end

        def replicate(collection:, shard: nil, create: false, read: false, update: false, delete: false)
          shards = shard.nil? ? ["*"] : Models.as_list(shard)
          Models.as_list(collection).flat_map do |c|
            shards.filter_map do |s|
              permission = ReplicatePermission.new(collection: c, shard: s, actions: [])
              permission.actions << ReplicateAction::CREATE if create
              permission.actions << ReplicateAction::READ if read
              permission.actions << ReplicateAction::UPDATE if update
              permission.actions << ReplicateAction::DELETE if delete
              permission unless permission.actions.empty?
            end
          end
        end

        def roles(role:, create: false, read: false, update: false, delete: false, scope: nil)
          Models.as_list(role).filter_map do |r|
            permission = RolesPermission.new(role: r, actions: [])
            permission.actions << RolesAction::READ if read
            permission.actions << RolesAction::CREATE if create
            permission.actions << RolesAction::UPDATE if update
            permission.actions << RolesAction::DELETE if delete
            permission.scope = RoleScope.from(scope) unless scope.nil?
            permission unless permission.actions.empty?
          end
        end

        def users(user:, create: false, read: false, update: false, delete: false, assign_and_revoke: false)
          Models.as_list(user).filter_map do |u|
            permission = UsersPermission.new(users: u, actions: [])
            permission.actions << UsersAction::CREATE if create
            permission.actions << UsersAction::READ if read
            permission.actions << UsersAction::UPDATE if update
            permission.actions << UsersAction::DELETE if delete
            permission.actions << UsersAction::ASSIGN_AND_REVOKE if assign_and_revoke
            permission unless permission.actions.empty?
          end
        end

        def backup(collection:, read: false, manage: false)
          Models.as_list(collection).filter_map do |c|
            permission = BackupsPermission.new(collection: c, actions: [])
            permission.actions << BackupsAction::READ if read
            permission.actions << BackupsAction::MANAGE if manage
            permission unless permission.actions.empty?
          end
        end

        def mcp(create: false, read: false, update: false)
          actions = []
          actions << MCPAction::CREATE if create
          actions << MCPAction::READ if read
          actions << MCPAction::UPDATE if update
          actions.empty? ? [] : [MCPPermission.new(actions: actions)]
        end

        def cluster(read: false)
          read ? [ClusterPermission.new(actions: [ClusterAction::READ])] : []
        end
      end
    end
  end
end
