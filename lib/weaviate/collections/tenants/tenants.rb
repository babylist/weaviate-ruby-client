# frozen_string_literal: true

require_relative "../batch/helpers"

module Weaviate
  module Collections
    module Tenants
      UPDATE_TENANT_BATCH_SIZE = 100

      # Port of weaviate.collections.tenants (_TenantsExecutor, sync): `collection.tenants`.
      class Tenants
        H = ::Weaviate::Collections::Batch::Helpers
        T = ::Weaviate::Classes::Tenants
        private_constant :H, :T

        def initialize(connection:, name:, validate_arguments: true)
          @connection = connection
          @name = name
          @validate_arguments = validate_arguments
        end

        # Create the specified tenants (names, Tenant or TenantCreate objects, or a list of them).
        # The collection must have been created with multi-tenancy enabled.
        def create(tenants)
          if @validate_arguments
            H.validate_input([[String, T::Tenant, T::TenantCreate, [:list_of, String, T::Tenant, T::TenantCreate]],
                              "tenants", tenants])
          end
          @connection.post("/schema/#{@name}/tenants",
                           weaviate_object: map_create_tenants(tenants),
                           error_msg: "Collection tenants may not have been added properly for #{@name}",
                           status_codes: codes(200, "Add collection tenants for #{@name}"))
          nil
        end

        # Remove the specified tenants (names or Tenant objects, or a list of them).
        def remove(tenants)
          if @validate_arguments
            H.validate_input([[String, T::Tenant, [:list_of, String, T::Tenant]], "tenants", tenants])
          end
          tenant_names =
            if tenants.is_a?(String) || tenants.is_a?(T::Tenant)
              [tenant_name(tenants)]
            else
              tenants.map { |tenant| tenant_name(tenant) }
            end
          @connection.delete("/schema/#{@name}/tenants",
                             weaviate_object: tenant_names,
                             error_msg: "Collection tenants may not have been deleted for #{@name}",
                             status_codes: codes(200, "Delete collection tenants for #{@name}"))
          nil
        end

        # Return all tenants of this collection as a Hash of name => Tenant.
        def get
          @connection.weaviate_version.supports_tenants_get_grpc ? get_with_grpc : get_with_rest
        end

        # Return the named tenants (names or Tenant objects) as a Hash of name => Tenant. Tenants that do not
        # exist are not included.
        def get_by_names(tenants)
          @connection.weaviate_version.check_is_at_least_1_25_0("The 'get_by_names' method")
          H.validate_input([[[:list_of, String, T::Tenant]], "names", tenants]) if @validate_arguments
          get_with_grpc(tenants: tenants)
        end

        # Return a specific tenant, or nil if it does not exist.
        def get_by_name(tenant)
          @connection.weaviate_version.check_is_at_least_1_25_0("The 'get_by_name' method")
          H.validate_input([[String, T::Tenant], "tenant", tenant]) if @validate_arguments
          name = tenant_name(tenant)
          if @connection.weaviate_version.is_lower_than(1, 28, 0)
            # such versions don't have RBAC so the gRPC filtering issue doesn't exist therein
            return get_with_grpc(tenants: [name])[name]
          end

          # >= 1.28.0: use REST as the gRPC API filters out tenants that are not accessible to the user (RBAC)
          res = @connection.get("/schema/#{@name}/tenants/#{name}",
                                error_msg: "Could not get tenant #{name} for collection #{@name}",
                                status_codes: codes([200, 404], "Get tenant #{name} for collection #{@name}"))
          return nil if res.status_code == 404

          data = res.json
          T::TenantOutput.new(name: data["name"], activity_status: T::TenantActivityStatus.from(data["activityStatus"]))
        end

        # Update the specified tenants (Tenant or TenantUpdate objects, or a list of them).
        def update(tenants)
          if @validate_arguments
            H.validate_input([[T::Tenant, T::TenantUpdate, [:list_of, T::Tenant, T::TenantUpdate]], "tenants",
                              tenants])
          end
          update_tenants(tenants)
        end

        # Check if a tenant exists for this collection.
        def exists(tenant)
          @connection.weaviate_version.check_is_at_least_1_25_0("The 'exists' method")
          H.validate_input([[String, T::Tenant], "tenant", tenant]) if @validate_arguments
          res = @connection.head("/schema/#{@name}/tenants/#{tenant_name(tenant)}",
                                 error_msg: "Could not check if tenant exists for #{@name}",
                                 status_codes: codes([200, 404], "Check if tenant exists for #{@name}"))
          res.status_code == 200
        end
        alias exists? exists

        # Activate the specified tenants.
        def activate(tenant)
          update_tenant_activity_status(tenant, T::TenantUpdateActivityStatus::ACTIVE)
        end

        # Deactivate the specified tenants.
        def deactivate(tenant)
          update_tenant_activity_status(tenant, T::TenantUpdateActivityStatus::INACTIVE)
        end

        # Offload the specified tenants.
        def offload(tenant)
          update_tenant_activity_status(tenant, T::TenantUpdateActivityStatus::OFFLOADED)
        end

        # Python _TenantsGRPC.map_activity_status
        def self.map_activity_status(status)
          case status
          when :TENANT_ACTIVITY_STATUS_COLD, :TENANT_ACTIVITY_STATUS_INACTIVE then T::TenantActivityStatus::INACTIVE
          when :TENANT_ACTIVITY_STATUS_HOT, :TENANT_ACTIVITY_STATUS_ACTIVE then T::TenantActivityStatus::ACTIVE
          when :TENANT_ACTIVITY_STATUS_FROZEN, :TENANT_ACTIVITY_STATUS_OFFLOADED then T::TenantActivityStatus::OFFLOADED
          when :TENANT_ACTIVITY_STATUS_FREEZING, :TENANT_ACTIVITY_STATUS_OFFLOADING
            T::TenantActivityStatus::OFFLOADING
          when :TENANT_ACTIVITY_STATUS_UNFREEZING, :TENANT_ACTIVITY_STATUS_ONLOADING
            T::TenantActivityStatus::ONLOADING
          else raise ArgumentError, "Unknown TenantActivityStatus: #{status}"
          end
        end

        private

        def codes(ok, error) = ::Weaviate::Connect::ExpectedStatusCodes.new(ok: ok, error: error)

        def tenant_name(tenant) = tenant.is_a?(T::TenantBase) ? tenant.name : tenant

        def get_with_rest
          res = @connection.get("/schema/#{@name}/tenants",
                                error_msg: "Could not get collection tenants for #{@name}",
                                status_codes: codes(200, "Get collection tenants for #{@name}"))
          res.json.to_h do |tenant|
            [tenant["name"], T::TenantOutput.new(name: tenant["name"], activity_status: tenant["activityStatus"])]
          end
        end

        def get_with_grpc(tenants: nil)
          names = tenants&.map { |tenant| tenant_name(tenant) }
          request = ::Weaviate::V1::TenantsGetRequest.new(
            collection: @name,
            names: (::Weaviate::V1::TenantNames.new(values: names) unless names.nil?)
          )
          res = @connection.grpc_tenants_get(request)
          res.tenants.to_h do |tenant|
            [tenant.name, T::TenantOutput.new(name: tenant.name,
                                              activity_status: self.class.map_activity_status(tenant.activity_status))]
          end
        end

        def map_create_tenant(tenant)
          return T::TenantCreate.new(name: tenant) if tenant.is_a?(String)

          if tenant.is_a?(T::Tenant)
            unless [T::TenantActivityStatus::ACTIVE, T::TenantActivityStatus::INACTIVE].include?(tenant.activity_status)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "Tenant activity status must be either 'ACTIVE' or 'INACTIVE'. Other statuses are read-only " \
                    "and cannot be set. Tenant: #{tenant.name} had status: #{tenant.activity_status}"
            end
            return T::TenantCreate.new(name: tenant.name, activity_status: tenant.activity_status)
          end
          tenant
        end

        def map_update_tenant(tenant)
          if tenant.is_a?(T::Tenant)
            unless [T::TenantActivityStatus::ACTIVE, T::TenantActivityStatus::INACTIVE,
                    T::TenantActivityStatus::OFFLOADED].include?(tenant.activity_status)
              raise ::Weaviate::Exceptions::WeaviateInvalidInputError,
                    "Tenant activity status must be one of 'ACTIVE', 'INACTIVE' or 'OFFLOADED'. Other statuses are " \
                    "read-only and cannot be set. Tenant: #{tenant.name} had status: #{tenant.activity_status}"
            end
            return T::TenantUpdate.new(name: tenant.name, activity_status: tenant.activity_status)
          end
          tenant
        end

        def map_create_tenants(tenants)
          if tenants.is_a?(String) || tenants.is_a?(T::Tenant) || tenants.is_a?(T::TenantCreate)
            [map_create_tenant(tenants).model_dump]
          else
            tenants.map { |tenant| map_create_tenant(tenant).model_dump }
          end
        end

        def map_update_tenants(tenants)
          if tenants.is_a?(T::Tenant) || tenants.is_a?(T::TenantUpdate)
            [[map_update_tenant(tenants).model_dump]]
          else
            tenants.each_slice(UPDATE_TENANT_BATCH_SIZE).map do |slice|
              slice.map { |tenant| map_update_tenant(tenant).model_dump }
            end
          end
        end

        def update_tenants(tenants)
          path = "/schema/#{@name}/tenants"
          map_update_tenants(tenants).each do |mapped_tenants|
            @connection.put(path, weaviate_object: mapped_tenants,
                                  error_msg: "Collection tenants may not have been updated properly for #{@name}",
                                  status_codes: codes(200, "Update collection tenants for #{@name}"))
          end
          nil
        end

        def update_tenant_activity_status(tenant, activity_status)
          if @validate_arguments
            H.validate_input([[String, T::Tenant, [:list_of, String, T::Tenant]], "tenant", tenant])
          end
          list = tenant.is_a?(String) || tenant.is_a?(T::Tenant) ? [tenant] : tenant
          update_tenants(list.map { |t| T::TenantUpdate.new(name: tenant_name(t), activity_status: activity_status) })
        end
      end
    end
  end
end
