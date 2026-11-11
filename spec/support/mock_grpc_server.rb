# frozen_string_literal: true

require "grpc"

# A single in-process gRPC server (started once per run) whose Weaviate service
# delegates to a swappable implementation object, so each example can install
# its own behaviour like the Python mock tests' MockWeaviateService classes.
#
#   MockGrpcServer.impl = Class.new do
#     def search(req, call) = Weaviate::V1::SearchReply.new
#   end.new
class MockGrpcServer
  class << self
    attr_accessor :impl

    def start(port: 23_537)
      return if @server

      @server = GRPC::RpcServer.new(pool_size: 20)
      @server.add_http2_port("0.0.0.0:#{port}", :this_port_is_insecure)
      @server.handle(HealthImpl.new)
      @server.handle(Dispatcher.new)
      @thread = Thread.new { @server.run }
      @server.wait_till_running(5)
    end

    def stop
      @server&.stop
      @thread&.join
      @server = nil
    end
  end

  class HealthImpl < Weaviate::V1::HealthService::Service
    def check(_req, _call)
      Weaviate::V1::WeaviateHealthCheckResponse.new(status: :SERVING)
    end
  end

  class Dispatcher < Weaviate::V1::WeaviateService::Service
    %i[search batch_objects batch_references batch_delete tenants_get aggregate].each do |rpc|
      define_method(rpc) do |req, call|
        impl = MockGrpcServer.impl
        raise GRPC::Unimplemented, rpc.to_s unless impl.respond_to?(rpc)

        impl.public_send(rpc, req, call)
      end
    end

    def batch_stream(requests, call)
      impl = MockGrpcServer.impl
      raise GRPC::Unimplemented, "batch_stream" unless impl.respond_to?(:batch_stream)

      impl.batch_stream(requests, call)
    end
  end
end
