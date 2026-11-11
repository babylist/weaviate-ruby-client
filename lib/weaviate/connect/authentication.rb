# frozen_string_literal: true

module Weaviate
  module Connect
    # Holds the OAuth2 token state for an OIDC-authenticated connection
    # (replaces authlib's OAuth2Client in the Python client).
    class OAuth2Session
      attr_accessor :token
      attr_reader :token_endpoint, :client_id

      def initialize(token_endpoint:, client_id:, token: {}, grant_type: nil, scope: [], client_secret: nil, http: nil)
        @token_endpoint = token_endpoint
        @client_id = client_id
        @token = token
        @grant_type = grant_type
        @scope = scope
        @client_secret = client_secret
        @http = http || HTTPClient.new
        @lock = Mutex.new
      end

      def access_token = token["access_token"]

      def fetch_token(username: nil, password: nil)
        # field order mirrors authlib so request bodies match the Python client
        form = { "grant_type" => @grant_type }
        if @grant_type == "password"
          form["username"] = username
          form["password"] = password
        end
        form["scope"] = @scope.join(" ") unless @scope.empty?
        form["client_id"] = client_id
        form["client_secret"] = @client_secret if @client_secret
        @lock.synchronize { @token = post_token(form) }
      end

      def refresh_token!
        form = { "grant_type" => "refresh_token", "refresh_token" => token["refresh_token"], "client_id" => client_id }
        new_token = post_token(form)
        new_token["refresh_token"] ||= token["refresh_token"]
        @lock.synchronize { @token = new_token }
      end

      private

      def post_token(form)
        res = @http.post(token_endpoint, form: form, headers: { "accept" => "application/json" },
                                         timeout: Authentication::AUTH_DEFAULT_TIMEOUT)
        unless res.ok?
          raise Exceptions::AuthenticationFailedError,
                "Failed to authenticate with OIDC: status #{res.status_code}, body #{res.body}"
        end
        res.json
      end
    end

    # Port of weaviate.connect.authentication._Auth
    class Authentication
      AUTH_DEFAULT_TIMEOUT = 5

      attr_reader :token_endpoint

      def initialize(oidc_config, credentials, http)
        @credentials = credentials
        @http = http
        @open_id_config_url = oidc_config.fetch("href")
        @client_id = oidc_config.fetch("clientId")
        @default_scopes = oidc_config["scopes"].is_a?(Array) ? oidc_config["scopes"] : []
        @oidc_config = oidc_config
        @token_endpoint = fetch_token_endpoint
        validate
      end

      def auth_session
        case @credentials
        when Auth::BearerToken then session_bearer_token(@credentials)
        when Auth::ClientCredentials then session_client_credentials(@credentials)
        when Auth::ClientPassword then session_user_pw(@credentials)
        else raise ArgumentError, "Unsupported credentials #{@credentials.class}"
        end
      end

      private

      def validate
        return unless @credentials.is_a?(Auth::ClientPassword)

        grants = @oidc_config["grant_types_supported"]
        if grants && !grants.include?("password")
          raise Exceptions::AuthenticationFailedError,
                "The grant_types supported by the third-party authentication service are insufficient. " \
                "Please add the 'password' grant type."
        end
        return unless @token_endpoint.start_with?("https://login.microsoftonline.com")

        raise Exceptions::AuthenticationFailedError,
              "Microsoft/azure does not recommend to authenticate using username and password and this method is " \
              "not supported by the ruby client."
      end

      def fetch_token_endpoint
        res = @http.get(@open_id_config_url, timeout: AUTH_DEFAULT_TIMEOUT)
        data = Util.decode_json_response_dict(res, "Get token endpoint")
        data.fetch("token_endpoint")
      end

      def session_bearer_token(config)
        token = { "access_token" => config.access_token }
        token["expires_in"] = config.expires_in unless config.expires_in.nil?
        token["refresh_token"] = config.refresh_token unless config.refresh_token.nil?
        Warnings.auth_no_refresh_token(config.expires_in) unless token.key?("refresh_token")
        OAuth2Session.new(token_endpoint: @token_endpoint, client_id: @client_id, token: token, http: @http)
      end

      def session_user_pw(config)
        scope = @default_scopes + config.scope_list
        session = OAuth2Session.new(token_endpoint: @token_endpoint, client_id: @client_id, grant_type: "password",
                                    scope: scope, http: @http)
        token = session.fetch_token(username: config.username, password: config.password)
        Warnings.auth_no_refresh_token(token["expires_in"]) unless token.key?("refresh_token")
        session
      end

      def session_client_credentials(config)
        scope = @default_scopes + config.scope_list
        if scope.empty?
          raise Exceptions::MissingScopeError unless @token_endpoint.start_with?("https://login.microsoftonline.com")

          scope = ["#{@client_id}/.default"]
        end
        session = OAuth2Session.new(token_endpoint: @token_endpoint, client_id: @client_id,
                                    grant_type: "client_credentials", scope: scope,
                                    client_secret: config.client_secret, http: @http)
        session.fetch_token
        session
      end
    end
  end
end
