# frozen_string_literal: true

module Weaviate
  module Classes
    # Port of weaviate.classes.tenants (weaviate.collections.classes.tenants).
    module Tenants
      # Port of _TenantActivistatusServerValues: values sent to Weaviate (needed for BC).
      module TenantActivityStatusServerValues
        extend ::Weaviate::StrEnum

        HOT = "HOT"
        COLD = "COLD"
        FROZEN = "FROZEN"
        OTHER = "OTHER" # placeholder for values that we receive from the server but do not send

        def self.from_string(value)
          case value
          when "ACTIVE", "HOT" then HOT
          when "INACTIVE", "COLD" then COLD
          when "OFFLOADED", "FROZEN" then FROZEN
          else OTHER
          end
        end
      end

      # The activity status of a tenant in Weaviate.
      #
      # ACTIVE: fully active; INACTIVE: not active, files stored locally; OFFLOADED: not active, files stored on
      # the cloud; OFFLOADING / ONLOADING: in transition. HOT/COLD/FROZEN are deprecated aliases of
      # ACTIVE/INACTIVE/OFFLOADED.
      module TenantActivityStatus
        extend ::Weaviate::StrEnum

        ACTIVE = "ACTIVE"
        INACTIVE = "INACTIVE"
        OFFLOADED = "OFFLOADED"
        OFFLOADING = "OFFLOADING"
        ONLOADING = "ONLOADING"
        HOT = "HOT"
        COLD = "COLD"
        FROZEN = "FROZEN"
      end

      # The activity status of a tenant to create in Weaviate.
      module TenantCreateActivityStatus
        extend ::Weaviate::StrEnum

        ACTIVE = "ACTIVE"
        INACTIVE = "INACTIVE"
        HOT = "HOT"
        COLD = "COLD"
      end

      # The activity status of a tenant to update in Weaviate.
      module TenantUpdateActivityStatus
        extend ::Weaviate::StrEnum

        ACTIVE = "ACTIVE"
        INACTIVE = "INACTIVE"
        OFFLOADED = "OFFLOADED"
        HOT = "HOT"
        COLD = "COLD"
        FROZEN = "FROZEN"
      end

      # Shared behaviour of Tenant / TenantCreate / TenantUpdate.
      class TenantBase < ::Weaviate::Model
        DEPRECATED = { "HOT" => "ACTIVE", "COLD" => "INACTIVE", "FROZEN" => "OFFLOADED" }.freeze

        attribute :name
        attribute :activity_status, default: "ACTIVE"

        # The value sent to Weaviate as `activityStatus` (Python `activityStatus` field).
        attr_reader :activity_status_server

        def self.status_enum = TenantActivityStatus

        def after_initialize
          raise ArgumentError, "#{self.class.name}: name must be a String" unless name.is_a?(String)

          self.activity_status = self.class.status_enum.from(activity_status)
          normalise_status(user_input?)
          @activity_status_server = TenantActivityStatusServerValues.from_string(activity_status)
        end

        # Python model_dump(): {"name": ..., "activityStatus": ...}
        def model_dump(exclude_none: false) # rubocop:disable Lint/UnusedMethodArgument
          { "name" => name, "activityStatus" => activity_status_server }
        end
        alias to_dict model_dump

        private

        def user_input? = true

        def normalise_status(warn)
          replacement = DEPRECATED[activity_status]
          return if replacement.nil? || !self.class.status_enum.include?(activity_status)

          ::Weaviate::Warnings.deprecated_tenant_type(activity_status, replacement) if warn
          self.activity_status = replacement
        end
      end

      # A tenant in Weaviate: `name` and `activity_status` (default ACTIVE).
      class Tenant < TenantBase
        def self.status_enum = TenantActivityStatus
      end

      # Port of TenantOutput: wrapper around Tenant for output purposes (no deprecation warnings).
      class TenantOutput < Tenant
        private

        def user_input? = false
      end

      # A tenant to create in Weaviate.
      class TenantCreate < TenantBase
        def self.status_enum = TenantCreateActivityStatus
      end

      # A tenant to update in Weaviate.
      class TenantUpdate < TenantBase
        def self.status_enum = TenantUpdateActivityStatus
      end

      # Python type aliases (weaviate.collections.tenants.types).
      TenantInputType = [String, Tenant].freeze
      TenantCreateInputType = [String, Tenant, TenantCreate].freeze
      TenantUpdateInputType = [Tenant, TenantUpdate].freeze
      TenantOutputType = Tenant
    end
  end
end
