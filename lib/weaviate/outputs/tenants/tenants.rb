# frozen_string_literal: true

module Weaviate
  module Outputs
    # Port of weaviate.outputs.tenants.
    module Tenants
      Tenant = ::Weaviate::Classes::Tenants::Tenant
      TenantActivityStatus = ::Weaviate::Classes::Tenants::TenantActivityStatus
      TenantOutputType = ::Weaviate::Classes::Tenants::Tenant
    end
  end
end
