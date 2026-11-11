# frozen_string_literal: true

require "time"
require_relative "../rbac/models"

module Weaviate
  # Port of weaviate.users (`client.users`).
  module Users
    USER_TYPE_DB = "db"
    USER_TYPE_OIDC = "oidc"

    UserTypes = ::Weaviate::RBAC::Models::UserTypes

    class OwnUser < ::Weaviate::Model
      attribute :user_id
      attribute :roles
      attribute :groups
    end

    class UserBase < ::Weaviate::Model
      attribute :user_id
      attribute :role_names
      attribute :user_type
    end

    class UserDB < UserBase
      attribute :active
      attribute :created_at, default: nil
      attribute :last_used_time, default: nil
      attribute :api_key_first_letters, default: nil
    end

    class UserOIDC < UserBase
      attribute :user_type, default: UserTypes::OIDC
    end

    # Go's zero time value, returned by the server when a timestamp is not set.
    GO_ZERO_TIME = Time.utc(1, 1, 1, 0, 0, 0)

    def self.parse_time(value)
      return nil if value.nil?

      Time.iso8601(value)
    rescue ArgumentError
      Time.parse(value)
    end

    def self.parse_last_used_at(value)
      return nil if value.nil?

      dt = parse_time(value)
      dt == GO_ZERO_TIME ? nil : dt
    end

    def self.user_db_from_weaviate(user)
      UserDB.new(
        user_id: user["userId"],
        role_names: user["roles"],
        active: user["active"],
        user_type: UserTypes.from(user["dbUserType"]),
        created_at: parse_time(user["createdAt"]),
        last_used_time: parse_last_used_at(user["lastUsedAt"]),
        api_key_first_letters: user["apiKeyFirstLetters"]
      )
    end
  end
end
