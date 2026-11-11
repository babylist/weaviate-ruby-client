# frozen_string_literal: true

require_relative "../rbac/models"

module Weaviate
  module Classes
    # Port of weaviate.classes.rbac
    module RBAC
      Actions = ::Weaviate::RBAC::Models::Actions
      Permissions = ::Weaviate::RBAC::Models::Permissions
      RoleScope = ::Weaviate::RBAC::Models::RoleScope
    end
  end
end
