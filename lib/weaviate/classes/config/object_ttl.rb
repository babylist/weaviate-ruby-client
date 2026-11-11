# frozen_string_literal: true

require_relative "base"
require_relative "fields"

# Port of weaviate/collections/classes/config_object_ttl.py
module Weaviate
  module Classes
    module Config
      # ObjectTTLConfigCreate
      class ObjectTTLConfigCreate < ConfigCreateModel
        include Fields

        field :enabled, :bool, default: true
        field :filterExpiredObjects, :bool
        field :deleteOn, :str
        field :defaultTtl, :int
      end

      # ObjectTTLConfigUpdate
      class ObjectTTLConfigUpdate < ConfigUpdateModel
        include Fields

        field :enabled, :bool, required: true
        field :filterExpiredObjects, :bool
        field :deleteOn, :str
        field :defaultTtl, :int
      end

      # _ObjectTTL (Configure.ObjectTTL). Python `timedelta` arguments are Integer seconds in Ruby
      # (anything responding to #to_i, e.g. ActiveSupport durations, is accepted too).
      module ObjectTTL
        def self.delete_by_update_time(time_to_live, filter_expired_objects: nil)
          ObjectTTLConfigCreate.new(
            deleteOn: "_lastUpdateTimeUnix",
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ConfigHelpers.seconds(time_to_live)
          )
        end

        def self.delete_by_creation_time(time_to_live, filter_expired_objects: nil)
          ObjectTTLConfigCreate.new(
            deleteOn: "_creationTimeUnix",
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ConfigHelpers.seconds(time_to_live)
          )
        end

        def self.delete_by_date_property(property_name, ttl_offset: nil, filter_expired_objects: nil)
          ttl_offset = ConfigHelpers.seconds(ttl_offset)
          ttl_offset = 0 if ttl_offset.nil?
          ObjectTTLConfigCreate.new(
            deleteOn: property_name,
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ttl_offset
          )
        end
      end

      # _ObjectTTLUpdate (Reconfigure.ObjectTTL)
      module ObjectTTLUpdate
        def self.disable
          ObjectTTLConfigUpdate.new(enabled: false)
        end

        def self.delete_by_update_time(time_to_live: nil, filter_expired_objects: nil)
          ObjectTTLConfigUpdate.new(
            enabled: true,
            deleteOn: "_lastUpdateTimeUnix",
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ConfigHelpers.seconds(time_to_live)
          )
        end

        def self.delete_by_creation_time(time_to_live: nil, filter_expired_objects: nil)
          ObjectTTLConfigUpdate.new(
            enabled: true,
            deleteOn: "_creationTimeUnix",
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ConfigHelpers.seconds(time_to_live)
          )
        end

        def self.delete_by_date_property(property_name: nil, ttl_offset: nil, filter_expired_objects: nil)
          ObjectTTLConfigUpdate.new(
            enabled: true,
            deleteOn: property_name,
            filterExpiredObjects: filter_expired_objects,
            defaultTtl: ConfigHelpers.seconds(ttl_offset)
          )
        end
      end
    end
  end
end
