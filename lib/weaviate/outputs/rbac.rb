# frozen_string_literal: true

require_relative "../rbac/models"

module Weaviate
  module Outputs
    # Port of weaviate.outputs.rbac
    module RBAC
      PermissionsOutputType = ::Weaviate::RBAC::Models::PermissionsOutputType
      BackupsPermissionOutput = ::Weaviate::RBAC::Models::BackupsPermissionOutput
      ClusterPermissionOutput = ::Weaviate::RBAC::Models::ClusterPermissionOutput
      CollectionsPermissionOutput = ::Weaviate::RBAC::Models::CollectionsPermissionOutput
      DataPermissionOutput = ::Weaviate::RBAC::Models::DataPermissionOutput
      NodesPermissionOutput = ::Weaviate::RBAC::Models::NodesPermissionOutput
      RolesPermissionOutput = ::Weaviate::RBAC::Models::RolesPermissionOutput
      RoleScope = ::Weaviate::RBAC::Models::RoleScope
      UsersPermissionOutput = ::Weaviate::RBAC::Models::UsersPermissionOutput
      UserAssignment = ::Weaviate::RBAC::Models::UserAssignment
      AliasPermissionOutput = ::Weaviate::RBAC::Models::AliasPermissionOutput
      ReplicatePermissionOutput = ::Weaviate::RBAC::Models::ReplicatePermissionOutput
      GroupsPermissionOutput = ::Weaviate::RBAC::Models::GroupsPermissionOutput
      TenantsPermissionOutput = ::Weaviate::RBAC::Models::TenantsPermissionOutput
      GroupAssignment = ::Weaviate::RBAC::Models::GroupAssignment
    end
  end
end
