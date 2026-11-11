# frozen_string_literal: true

module Weaviate
  module Connect
    ExpectedStatusCodes = Struct.new(:ok, :error, keyword_init: true) do
      def initialize(ok:, error:)
        super(ok: Array(ok), error: error)
      end
    end

    # Port of weaviate.retry._Retry: retries gRPC calls that fail with UNAVAILABLE
    # using exponential backoff.
    class Retry
      def initialize(n = 4, sleeper: ->(s) { sleep(s) })
        @n = n
        @sleeper = sleeper
      end

      def with_exponential_backoff(count, error)
        yield
      rescue ::GRPC::Unavailable => e
        @sleeper.call(2**count)
        raise Exceptions::WeaviateRetryError.new(e.message, count) if count > @n

        with_exponential_backoff(count + 1, error) { yield }
      end
    end

    # Port of weaviate.connect.v4.ConnectionSync: owns the REST client, the gRPC
    # stub, authentication and token refresh.
    class Connection
      PYPI_PACKAGE_URL = "https://rubygems.org/api/v1/gems/weaviate-client.json"

      attr_reader :url, :timeout_config, :embedded_db, :connection_params
      attr_accessor :weaviate_version

      def initialize(connection_params:, auth_client_secret: nil, timeout_config: Config::Timeout.new,
                     proxies: nil, trust_env: false, additional_headers: nil,
                     connection_config: Config::ConnectionConfig.new, embedded_db: nil,
                     skip_init_checks: false, grpc_config: nil)
        @connection_params = connection_params
        @url = connection_params.http_url
        @embedded_db = embedded_db
        @api_version_path = "/v1"
        @additional_headers = {}
        @auth = auth_client_secret
        @client = nil
        @oauth = nil
        @grpc_stub = nil
        @timeout_config = timeout_config
        @connection_config = connection_config
        @trust_env = trust_env
        @weaviate_version = ServerVersion.from_string("")
        @grpc_max_msg_size = nil
        @connected = false
        @skip_init_checks = skip_init_checks
        @grpc_config = grpc_config
        @refresh_thread = nil
        @shutdown = nil

        embedded_suffix = embedded_db.nil? ? "" : "-embedded"
        @headers = {
          "content-type" => "application/json",
          "X-Weaviate-Client" => "weaviate-client-ruby/#{VERSION}-sync#{embedded_suffix}"
        }
        if Util.is_weaviate_domain(connection_params.http.host)
          @headers["X-Weaviate-Cluster-URL"] = "https://#{connection_params.http.host}"
        end
        unless additional_headers.nil?
          raise TypeError, "additional_headers must be a Hash" unless additional_headers.is_a?(Hash)

          @additional_headers = additional_headers.transform_keys(&:to_s)
          @additional_headers.each do |key, value|
            raise Exceptions::WeaviateInvalidInputError, "Value for key '#{key}' in headers cannot be None." if value.nil?

            @headers[key.downcase] = value
          end
        end

        @proxies = Connect.get_proxies(proxies, trust_env)

        if @headers.key?("authorization") && !auth_client_secret.nil?
          Warnings.auth_header_and_auth_secret
          @headers.delete("authorization")
        end
        @headers["authorization"] = "Bearer #{auth_client_secret.api_key}" if auth_client_secret.is_a?(Auth::APIKey)

        prepare_grpc_headers
      end

      attr_reader :additional_headers, :headers, :proxies, :grpc_max_msg_size

      def is_connected # rubocop:disable Naming/PredicatePrefix
        @connected
      end
      alias connected? is_connected

      def server_version = @weaviate_version.to_s
      def get_proxies = @proxies

      def set_integrations(integrations_config)
        integrations_config.each do |integration|
          @headers.merge!(integration.to_header)
          @additional_headers.merge!(integration.to_header)
        end
        prepare_grpc_headers
      end

      def get_current_bearer_token
        return @headers["authorization"] if @headers.key?("authorization")
        return "Bearer #{@oauth.access_token}" if @oauth

        ""
      end

      def grpc_headers
        return @grpc_metadata if @auth.nil? || @auth.is_a?(Auth::APIKey)

        @grpc_metadata.merge("authorization" => get_current_bearer_token)
      end

      def grpc_stub
        raise Exceptions::WeaviateClosedClientError unless is_connected

        @grpc_stub
      end

      def connect(force: false)
        return if @connected && !force

        open_connections_rest
        begin
          meta = get_meta(check_is_connected: false)
          @weaviate_version = ServerVersion.from_string(meta["version"])
          @grpc_max_msg_size = Integer(meta["grpcMaxMessageSize"]) if meta.key?("grpcMaxMessageSize")
        rescue Exceptions::WeaviateConnectionError, HTTPClient::ConnectError, OpenSSL::SSL::SSLError => e
          @connected = false
          raise Exceptions::WeaviateStartUpError, "Could not connect to Weaviate:#{e.message}."
        end

        open_connection_grpc
        unless @embedded_db.nil?
          begin
            wait_for_weaviate(10)
          rescue Exceptions::WeaviateStartUpError
            @embedded_db.stop
            @connected = false
            raise
          end
        end

        if @weaviate_version.is_lower_than(1, 27, 0)
          @connected = false
          raise Exceptions::WeaviateStartUpError,
                "Weaviate version #{@weaviate_version} is not supported. Please use Weaviate version 1.27.0 or higher."
        end

        unless @skip_init_checks
          begin
            ping_grpc
          rescue StandardError
            @connected = false
            raise
          end
        end
        @connected = true
      end

      def wait_for_weaviate(startup_period)
        (startup_period + 1).times do |i|
          res = get("/.well-known/ready", check_is_connected: false)
          return if res.ok?
        rescue Exceptions::WeaviateConnectionError, Exceptions::WeaviateTimeoutError
          nil
        ensure
          sleep(1) if i < startup_period && !res&.ok?
        end
        raise Exceptions::WeaviateStartUpError,
              "Weaviate did not start up in #{startup_period} seconds. Either the Weaviate URL #{@url} is wrong or " \
              "Weaviate did not start up in the interval given in 'startup_period'."
      end

      def ping_grpc
        stub = @connection_params.grpc_stub(V1::HealthService::Stub, proxies: @proxies,
                                                                     grpc_config: @grpc_config)
        res = stub.check(V1::WeaviateHealthCheckRequest.new, deadline: deadline(@timeout_config.init),
                                                              metadata: grpc_headers || {})
        return if res.status == :SERVING

        raise Exceptions::WeaviateGRPCUnavailableError.new("v#{server_version}", @connection_params.grpc_address)
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateGRPCUnavailableError.new("v#{server_version}", @connection_params.grpc_address,
                                                           error: e)
      end

      def close
        @embedded_db&.stop
        cancel_background_token_refresh
        @client&.close
        @client = nil
        @grpc_stub = nil
        @connected = false
        nil
      end

      # --- REST -----------------------------------------------------------

      def delete(path, weaviate_object: nil, params: nil, error_msg: "", status_codes: nil)
        send_request("DELETE", path, weaviate_object: weaviate_object, params: params, error_msg: error_msg,
                                     status_codes: status_codes)
      end

      def patch(path, weaviate_object:, params: nil, error_msg: "", status_codes: nil)
        send_request("PATCH", path, weaviate_object: weaviate_object, params: params, error_msg: error_msg,
                                    status_codes: status_codes)
      end

      def post(path, weaviate_object:, params: nil, error_msg: "", status_codes: nil, is_gql_query: false)
        send_request("POST", path, weaviate_object: weaviate_object, params: params, error_msg: error_msg,
                                   status_codes: status_codes, is_gql_query: is_gql_query)
      end

      def put(path, weaviate_object:, params: nil, error_msg: "", status_codes: nil)
        send_request("PUT", path, weaviate_object: weaviate_object, params: params, error_msg: error_msg,
                                  status_codes: status_codes)
      end

      def get(path, params: nil, error_msg: "", status_codes: nil, check_is_connected: true)
        send_request("GET", path, params: params, error_msg: error_msg, status_codes: status_codes,
                                  check_is_connected: check_is_connected)
      end

      def head(path, params: nil, error_msg: "", status_codes: nil)
        send_request("HEAD", path, params: params, error_msg: error_msg, status_codes: status_codes)
      end

      def get_meta(check_is_connected: true)
        res = get("/meta", check_is_connected: check_is_connected)
        Util.decode_json_response_dict(res, "Meta endpoint")
      end

      def get_open_id_configuration
        res = get("/.well-known/openid-configuration")
        return Util.decode_json_response_dict(res, "OpenID Configuration") if res.status_code == 200
        return nil if res.status_code == 404

        raise Exceptions::UnexpectedStatusCodeError.new("Meta endpoint", res)
      end

      # --- gRPC -----------------------------------------------------------

      def grpc_search(request)
        Retry.new(4).with_exponential_backoff(0, "Searching in collection #{request.collection}") do
          grpc_stub.search(request, metadata: grpc_headers || {}, deadline: deadline(@timeout_config.query))
        end
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateQueryError.new(e.details.to_s, "GRPC search")
      rescue Exceptions::WeaviateRetryError => e
        raise Exceptions::WeaviateQueryError.new(e.message, "GRPC search")
      end

      # Returns { index => error message } for failed objects.
      def grpc_batch_objects(request, timeout:, max_retries:)
        res = Retry.new(max_retries).with_exponential_backoff(0, "Batch objects") do
          grpc_stub.batch_objects(request, metadata: grpc_headers || {}, deadline: deadline(timeout))
        end
        res.errors.to_h { |err| [err.index, err.error] }
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateBatchError, e.details.to_s
      end

      def grpc_batch_references(request, timeout:, max_retries:)
        res = Retry.new(max_retries).with_exponential_backoff(0, "Batch references") do
          grpc_stub.batch_references(request, metadata: grpc_headers || {}, deadline: deadline(timeout))
        end
        res.errors.to_h { |err| [err.index, err.error] }
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateBatchError, e.details.to_s
      end

      # Bidirectional stream. +requests+ is an Enumerable of BatchStreamRequest;
      # yields each BatchStreamReply.
      def grpc_batch_stream(requests, &block)
        opts = { metadata: grpc_headers || {} }
        opts[:deadline] = deadline(@timeout_config.stream) if @timeout_config.stream
        grpc_stub.batch_stream(requests, **opts).each(&block)
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::Aborted
        raise Exceptions::BatchStreamShutdownError
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateBatchStreamError,
              "#{Exceptions.grpc_code_name(e.code)}(#{e.details})"
      end

      def grpc_batch_delete(request)
        grpc_stub.batch_delete(request, metadata: grpc_headers || {}, deadline: deadline(@timeout_config.insert))
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateDeleteManyError, "[#{Exceptions.grpc_code_name(e.code)}] #{e.details}"
      end

      def grpc_tenants_get(request)
        Retry.new.with_exponential_backoff(0, "Get tenants for collection #{request.collection}") do
          grpc_stub.tenants_get(request, metadata: grpc_headers || {}, deadline: deadline(@timeout_config.query))
        end
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateTenantGetError, e.details.to_s
      end

      def grpc_aggregate(request)
        Retry.new(4).with_exponential_backoff(0, "Searching in collection #{request.collection}") do
          grpc_stub.aggregate(request, metadata: grpc_headers || {}, deadline: deadline(@timeout_config.query))
        end
      rescue ::GRPC::PermissionDenied => e
        raise Exceptions::InsufficientPermissionsError, e
      rescue ::GRPC::BadStatus => e
        raise Exceptions::WeaviateQueryError.new(e.message, "GRPC search")
      rescue Exceptions::WeaviateRetryError => e
        raise Exceptions::WeaviateQueryError.new(e.message, "GRPC search")
      end

      private

      def deadline(seconds)
        Time.now + seconds
      end

      def prepare_grpc_headers
        meta = {}
        meta["x-weaviate-client"] = @headers["X-Weaviate-Client"] if @headers.key?("X-Weaviate-Client")
        @additional_headers.each do |key, val|
          meta[key.downcase] = val.to_s if !val.nil? && key.downcase != "x-weaviate-client"
        end
        unless @auth.nil?
          meta["x-weaviate-cluster-url"] = @headers["X-Weaviate-Cluster-URL"] if @headers.key?("X-Weaviate-Cluster-URL")
          meta["authorization"] =
            @auth.is_a?(Auth::APIKey) ? "Bearer #{@auth.api_key}" : "dummy_will_be_refreshed_for_each_call"
        end
        @grpc_metadata = meta.empty? ? nil : meta
      end

      def make_client
        HTTPClient.new(headers: @headers, proxies: @proxies,
                       connect_timeout: 5, retries: @connection_config.session_pool_max_retries)
      end

      def open_connection_grpc
        @grpc_stub = @connection_params.grpc_stub(V1::WeaviateService::Stub, proxies: @proxies,
                                                                             grpc_msg_size: @grpc_max_msg_size,
                                                                             grpc_config: @grpc_config)
      end

      def open_connections_rest
        @client = make_client
        return if @auth.is_a?(Auth::APIKey)
        return if @headers.key?("authorization") && @auth.nil?
        return if @skip_init_checks && @auth.nil?

        oidc_url = "#{@url}#{@api_version_path}/.well-known/openid-configuration"
        begin
          response = @client.get(oidc_url, timeout: @timeout_config.init)
        rescue StandardError => e
          raise Exceptions::WeaviateConnectionError, "Error: #{e.message}. \nIs Weaviate running and reachable at #{@url}?"
        end
        process_oidc_response(response, oidc_url)
      end

      def process_oidc_response(response, oidc_url)
        if response.status_code == 200
          resp = begin
            response.json
          rescue JSON::ParserError
            Warnings.auth_cannot_parse_oidc_config(oidc_url)
            return
          end
          if @auth.nil?
            msg = "No login credentials provided. The weaviate instance at #{@url} requires login credentials.\n\n" \
                  "Please check our documentation at https://weaviate.io/developers/weaviate/client-libraries " \
                  "for more information about how to use authentication."
            if Util.is_weaviate_domain(@url)
              msg += "\n\nYou can instantiate the client with login credentials for Weaviate Cloud using\n\n" \
                     "  client = Weaviate.connect_to_weaviate_cloud(cluster_url: YOUR_WEAVIATE_URL, " \
                     "auth_credentials: Weaviate::Auth.api_key(\"YOUR_API_KEY\"))"
            end
            raise Exceptions::AuthenticationFailedError, msg
          end
          auth = Authentication.new(resp, @auth, make_client)
          @oauth = auth.auth_session
          create_background_token_refresh(@auth.is_a?(Auth::ClientCredentials) ? auth : nil)
        elsif response.status_code == 404 && !@auth.nil?
          Warnings.auth_with_anon_weaviate
        end
      end

      def create_background_token_refresh(auth = nil)
        return if !@oauth.token.key?("refresh_token") && auth.nil?

        cancel_background_token_refresh
        shutdown = Queue.new
        @shutdown = shutdown
        refresh_in = (@oauth.token["expires_in"] || 60).to_i - 30
        @refresh_thread = Thread.new do
          Thread.current.name = "TokenRefresh"
          loop do
            break if wait_or_shutdown(shutdown, [refresh_in, 1].max)

            begin
              if @oauth.token.key?("refresh_token")
                @oauth.refresh_token!
              else
                @oauth.token = auth.auth_session.token
              end
              refresh_in = (@oauth.token["expires_in"] || 60).to_i - 30
            rescue StandardError => e
              refresh_in = 1
              Warnings.token_refresh_failed(e)
            end
          end
        end
      end

      def wait_or_shutdown(queue, seconds)
        deadline = Time.now + seconds
        loop do
          return true unless queue.empty?
          return false if Time.now >= deadline

          sleep([0.1, deadline - Time.now].min)
        end
      end

      def cancel_background_token_refresh
        @shutdown&.push(true)
        @refresh_thread&.join(1)
        @refresh_thread = nil
        @shutdown = nil
      end

      def latest_headers
        return @headers if @headers.key?("authorization")

        token = get_current_bearer_token
        return @headers if token.empty?

        @headers.merge("authorization" => token)
      end

      def timeout_for(method, is_gql_query)
        case method
        when "DELETE", "PATCH", "PUT" then @timeout_config.insert
        when "GET", "HEAD" then @timeout_config.query
        when "POST" then is_gql_query ? @timeout_config.query : @timeout_config.insert
        end
      end

      def send_request(method, path, error_msg:, status_codes:, weaviate_object: nil, params: nil,
                       is_gql_query: false, check_is_connected: true)
        raise Exceptions::WeaviateClosedClientError if check_is_connected && !is_connected
        raise Exceptions::WeaviateClosedClientError if @client.nil?

        @embedded_db&.ensure_running
        begin
          res = @client.request(method, @url + @api_version_path + path, json: weaviate_object, params: params,
                                                                          headers: latest_headers,
                                                                          timeout: timeout_for(method, is_gql_query))
        rescue HTTPClient::ConnectError => e
          raise Exceptions::WeaviateConnectionError, "#{error_msg} #{e.message}".strip
        rescue HTTPClient::ReadTimeout => e
          raise Exceptions::WeaviateTimeoutError, "#{error_msg} #{e.message}".strip
        rescue RuntimeError
          raise Exceptions::WeaviateClosedClientError
        end
        raise Exceptions::InsufficientPermissionsError, res if res.status_code == 403
        if !status_codes.nil? && !status_codes.ok.include?(res.status_code)
          raise Exceptions::UnexpectedStatusCodeError.new(error_msg, res)
        end

        res
      end
    end
  end
end
