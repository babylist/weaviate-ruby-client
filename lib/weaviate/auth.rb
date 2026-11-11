# frozen_string_literal: true

module Weaviate
  # Port of weaviate.auth
  module Auth
    def self.scope_list(scope)
      case scope
      when nil then []
      when String then scope.split(" ")
      when Array then scope
      else raise TypeError, "scope must be a String or Array of Strings"
      end
    end

    class ClientCredentials < Model
      attribute :client_secret
      attribute :scope, default: nil

      def scope_list = Auth.scope_list(scope)
    end

    class ClientPassword < Model
      attribute :username
      attribute :password
      attribute :scope, default: nil

      def scope_list = Auth.scope_list(scope)
    end

    class BearerToken < Model
      attribute :access_token
      attribute :expires_in, default: 60
      attribute :refresh_token, default: nil

      def after_initialize
        Warnings.auth_negative_expiration_time(expires_in) if expires_in&.negative?
      end
    end

    class APIKey < Model
      attribute :api_key
    end

    def self.api_key(api_key)
      APIKey.new(api_key: api_key)
    end

    def self.client_credentials(client_secret, scope: nil)
      ClientCredentials.new(client_secret: client_secret, scope: scope)
    end

    def self.client_password(username, password, scope: nil)
      ClientPassword.new(username: username, password: password, scope: scope)
    end

    def self.bearer_token(access_token, expires_in: 60, refresh_token: nil)
      BearerToken.new(access_token: access_token, expires_in: expires_in, refresh_token: refresh_token)
    end

    # v3-style aliases kept by the Python client
    AuthApiKey = APIKey
    AuthBearerToken = BearerToken
    AuthClientCredentials = ClientCredentials
    AuthClientPassword = ClientPassword
  end
end
