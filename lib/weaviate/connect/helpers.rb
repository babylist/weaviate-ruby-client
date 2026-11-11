# frozen_string_literal: true

require "uri"

module Weaviate
  # Port of weaviate.connect.helpers. Each helper connects immediately; pass a
  # block to have the client closed automatically when the block returns.
  module ConnectHelpers
    module_function

    def connect_to_weaviate_cloud(cluster_url:, auth_credentials:, headers: nil, additional_config: nil,
                                  skip_init_checks: false, &block)
      if [Auth::BearerToken, Auth::ClientPassword, Auth::ClientCredentials].any? { |k| auth_credentials.is_a?(k) }
        Warnings.oidc_with_wcd_deprecated
      end
      cluster_url, grpc_host = parse_weaviate_cloud_cluster_url(cluster_url)
      connect!(
        Client.new(
          connection_params: Connect::ConnectionParams.new(
            http: Connect::ProtocolParams.new(host: cluster_url, port: 443, secure: true),
            grpc: Connect::ProtocolParams.new(host: grpc_host, port: 443, secure: true)
          ),
          auth_client_secret: parse_auth_credentials(auth_credentials),
          additional_headers: headers,
          additional_config: additional_config,
          skip_init_checks: skip_init_checks
        ), &block
      )
    end

    def connect_to_wcs(cluster_url:, auth_credentials:, headers: nil, additional_config: nil, skip_init_checks: false,
                       &block)
      connect_to_weaviate_cloud(cluster_url: cluster_url, auth_credentials: auth_credentials, headers: headers,
                                additional_config: additional_config, skip_init_checks: skip_init_checks, &block)
    end

    def connect_to_local(host: "localhost", port: 8080, grpc_port: 50_051, headers: nil, additional_config: nil,
                         skip_init_checks: false, auth_credentials: nil, &block)
      connect!(
        Client.new(
          connection_params: Connect::ConnectionParams.new(
            http: Connect::ProtocolParams.new(host: host, port: port, secure: false),
            grpc: Connect::ProtocolParams.new(host: host, port: grpc_port, secure: false)
          ),
          additional_headers: headers,
          additional_config: additional_config,
          skip_init_checks: skip_init_checks,
          auth_client_secret: parse_auth_credentials(auth_credentials)
        ), &block
      )
    end

    def connect_to_embedded(hostname: "127.0.0.1", port: 8079, grpc_port: 50_050, headers: nil, additional_config: nil,
                            version: Embedded::WEAVIATE_VERSION, persistence_data_path: nil, binary_path: nil,
                            environment_variables: nil, &block)
      opts = { hostname: hostname, port: port, grpc_port: grpc_port, version: version,
               additional_env_vars: environment_variables }
      opts[:persistence_data_path] = persistence_data_path unless persistence_data_path.nil?
      opts[:binary_path] = binary_path unless binary_path.nil?
      connect!(
        Client.new(embedded_options: Embedded::EmbeddedOptions.new(**opts), additional_headers: headers,
                   additional_config: additional_config), &block
      )
    end

    def connect_to_custom(http_host:, http_port:, http_secure:, grpc_host:, grpc_port:, grpc_secure:, headers: nil,
                          additional_config: nil, auth_credentials: nil, skip_init_checks: false, &block)
      connect!(
        Client.new(
          connection_params: Connect::ConnectionParams.from_params(
            http_host: http_host, http_port: http_port, http_secure: http_secure,
            grpc_host: grpc_host, grpc_port: grpc_port, grpc_secure: grpc_secure
          ),
          auth_client_secret: parse_auth_credentials(auth_credentials),
          additional_headers: headers,
          additional_config: additional_config,
          skip_init_checks: skip_init_checks
        ), &block
      )
    end

    def connect!(client)
      begin
        client.connect
      rescue StandardError
        client.close
        raise
      end
      return client unless block_given?

      begin
        yield client
      ensure
        client.close
      end
    end

    def parse_weaviate_cloud_cluster_url(cluster_url)
      raise TypeError, "cluster_url must be a String" unless cluster_url.is_a?(String)

      cluster_url = URI.parse(cluster_url).host if cluster_url.start_with?("http")
      if cluster_url.end_with?(".weaviate.network")
        ident, domain = cluster_url.split(".", 2)
        grpc_host = "#{ident}.grpc.#{domain}"
      else
        grpc_host = "grpc-#{cluster_url}"
      end
      [cluster_url, grpc_host]
    end

    def parse_auth_credentials(creds)
      case creds
      when String then Auth.api_key(creds)
      when Auth::BearerToken, Auth::ClientPassword, Auth::ClientCredentials, Auth::APIKey, nil then creds
      else raise ArgumentError, "Invalid auth credentials provided."
      end
    end
  end


  %i[connect_to_weaviate_cloud connect_to_wcs connect_to_local connect_to_embedded connect_to_custom].each do |m|
    define_singleton_method(m) { |*args, **kwargs, &block| ConnectHelpers.public_send(m, *args, **kwargs, &block) }
  end
end
