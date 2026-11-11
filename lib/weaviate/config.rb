# frozen_string_literal: true

module Weaviate
  # Port of weaviate.config
  module Config
    class ConnectionConfig < Model
      attribute :session_pool_connections, default: 20
      attribute :session_pool_maxsize, default: 100
      attribute :session_pool_max_retries, default: 3
      attribute :session_pool_timeout, default: 5

      def after_initialize
        %i[session_pool_connections session_pool_maxsize session_pool_max_retries session_pool_timeout].each do |name|
          value = public_send(name)
          raise TypeError, "#{name} must be Integer, received #{value.class}" unless value.is_a?(Integer)
        end
      end
    end

    class Timeout < Model
      attribute :query, default: 30
      attribute :insert, default: 90
      attribute :init, default: 2
      attribute :stream, default: nil

      def after_initialize
        { query: query, insert: insert, init: init, stream: stream }.each do |name, value|
          next if value.nil? && name == :stream
          raise ArgumentError, "#{name} must be a non-negative number" unless value.is_a?(Numeric) && value >= 0
        end
      end
    end

    class Proxies < Model
      attribute :http, default: nil
      attribute :https, default: nil
      attribute :grpc, default: nil

      def to_proxy_hash
        to_h.compact.transform_keys(&:to_s)
      end
    end

    # channel_args: Hash of gRPC channel args (e.g. {"grpc.keepalive_time_ms" => 10_000}).
    # credentials: a GRPC::Core::ChannelCredentials for secure channels.
    class GrpcConfig < Model
      attribute :channel_options, default: nil
      attribute :credentials, default: nil
    end

    class AdditionalConfig < Model
      attribute :connection, default: -> { ConnectionConfig.new }
      attribute :proxies, default: nil
      attribute :timeout, default: -> { Timeout.new }
      attribute :trust_env, default: false
      attribute :grpc_config, default: nil

      def after_initialize
        return unless timeout.is_a?(Array)

        @timeout = Timeout.new(query: timeout[0], insert: timeout[1])
      end
    end
  end
end
