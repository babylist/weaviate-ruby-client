# frozen_string_literal: true

require "uri"
require "openssl"

module Weaviate
  module Connect
    MAX_GRPC_MESSAGE_LENGTH = 104_858_000 # 10mb, synchronised with the gRPC server

    class ProtocolParams < Model
      attribute :host
      attribute :port
      attribute :secure

      def after_initialize
        raise ArgumentError, "host must not be empty" if host.nil? || host.to_s.empty?
        raise ArgumentError, "port must be an Integer" unless port.is_a?(Integer)
        raise ArgumentError, "port must be between 0 and 65535" if port.negative? || port > 65_535
        raise ArgumentError, "secure must be a boolean" unless [true, false].include?(secure)
      end

      def is_gcp # rubocop:disable Naming/PredicatePrefix
        host.include?("gcp.weaviate.cloud")
      end
    end

    class ConnectionParams < Model
      attribute :http
      attribute :grpc

      def self.from_url(url, grpc_port, grpc_secure: false)
        parsed = URI.parse(url)
        raise ArgumentError, "Unsupported scheme: #{parsed.scheme}" unless %w[http https].include?(parsed.scheme)

        port = parsed.port || (parsed.scheme == "https" ? 443 : 80)
        new(
          http: ProtocolParams.new(host: parsed.host, port: port, secure: parsed.scheme == "https"),
          grpc: ProtocolParams.new(host: parsed.host, port: grpc_port, secure: grpc_secure || parsed.scheme == "https")
        )
      end

      def self.from_params(http_host:, http_port:, http_secure:, grpc_host:, grpc_port:, grpc_secure:)
        new(
          http: ProtocolParams.new(host: http_host, port: http_port, secure: http_secure),
          grpc: ProtocolParams.new(host: grpc_host, port: grpc_port, secure: grpc_secure)
        )
      end

      def after_initialize
        raise TypeError, "http must be a ProtocolParams" unless http.is_a?(ProtocolParams)
        raise TypeError, "grpc must be a ProtocolParams" unless grpc.is_a?(ProtocolParams)
        return unless http.host == grpc.host && http.port == grpc.port

        raise ArgumentError, "http.port and grpc.port must be different if using the same host"
      end

      def is_gcp_on_wcd # rubocop:disable Naming/PredicatePrefix
        http.host.downcase.include?("gcp") && Util.is_weaviate_domain(http.host)
      end

      def grpc_address = [grpc.host, grpc.port]
      def grpc_target = "#{grpc.host}:#{grpc.port}"
      def http_scheme = http.secure ? "https" : "http"
      def http_url = "#{http_scheme}://#{http.host}:#{http.port}"

      # gRPC channel args (Python `options`), including user channel_options.
      def grpc_channel_args(proxies: {}, grpc_msg_size: nil, grpc_config: nil)
        grpc_msg_size ||= MAX_GRPC_MESSAGE_LENGTH
        args = {
          "grpc.max_send_message_length" => grpc_msg_size,
          "grpc.max_receive_message_length" => grpc_msg_size,
          "grpc.default_authority" => grpc.host
        }
        args["grpc.http_proxy"] = proxies["grpc"] if proxies["grpc"]
        args.merge!(grpc_config.channel_options.to_h.transform_keys(&:to_s)) if grpc_config&.channel_options
        args
      end

      # Credentials for the channel: user-supplied, else the system CA bundle (Python
      # uses certifi), unless GRPC_DEFAULT_SSL_ROOTS_FILE_PATH is set (grpc reads it itself).
      def grpc_channel_credentials(grpc_config: nil)
        return :this_channel_is_insecure unless grpc.secure
        return grpc_config.credentials if grpc_config&.credentials

        Connect.default_grpc_credentials
      end

      # Build a GRPC stub for +stub_class+ using these params.
      def grpc_stub(stub_class, proxies: {}, grpc_msg_size: nil, grpc_config: nil)
        stub_class.new(grpc_target, grpc_channel_credentials(grpc_config: grpc_config),
                       channel_args: grpc_channel_args(proxies: proxies, grpc_msg_size: grpc_msg_size,
                                                       grpc_config: grpc_config))
      end
    end

    def self.default_grpc_credentials
      return ::GRPC::Core::ChannelCredentials.new if ENV["GRPC_DEFAULT_SSL_ROOTS_FILE_PATH"]

      bundle = [ENV.fetch("SSL_CERT_FILE", nil), OpenSSL::X509::DEFAULT_CERT_FILE].compact.find { |f| File.file?(f) }
      bundle ? ::GRPC::Core::ChannelCredentials.new(File.read(bundle)) : ::GRPC::Core::ChannelCredentials.new
    end

    # Port of weaviate.connect.base._get_proxies
    def self.get_proxies(proxies, trust_env)
      unless proxies.nil?
        return { "http" => proxies, "https" => proxies, "grpc" => proxies } if proxies.is_a?(String)
        return proxies.transform_keys(&:to_s) if proxies.is_a?(Hash)
        return proxies.to_proxy_hash if proxies.is_a?(Config::Proxies)

        raise TypeError, "If 'proxies' is not nil, it must be a Hash, String, or Weaviate::Config::Proxies. " \
                         "Given type: #{proxies.class}."
      end
      return {} unless trust_env

      result = {}
      %w[http https grpc].each do |key|
        value = ENV["#{key.upcase}_PROXY"] || ENV["#{key}_proxy"]
        result[key] = value if value && !value.empty?
      end
      result
    end
  end
end
