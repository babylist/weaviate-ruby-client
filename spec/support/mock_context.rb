# frozen_string_literal: true

# Shared fixtures mirroring weaviate-python-client/mock_tests/conftest.py
module MockContext
  MOCK_IP = "127.0.0.1"
  MOCK_PORT = 23_536
  MOCK_PORT_GRPC = 23_537
  CLIENT_ID = "DoesNotMatter"
  MOCK_SERVER_URL = "http://#{MOCK_IP}:#{MOCK_PORT}".freeze

  MOCK_CLASS = JSON.parse(File.read(File.join(__dir__, "mock_class.json"))).freeze

  def self.http_server
    @http_server ||= MockHTTPServer.new(host: MOCK_IP, port: MOCK_PORT)
  end
end

RSpec.shared_context "mock weaviate" do
  let(:httpserver) { MockContext.http_server }

  before do
    MockGrpcServer.start(port: MockContext::MOCK_PORT_GRPC)
    MockGrpcServer.impl = nil
    httpserver.clear
    httpserver.expect_request("/v1/.well-known/ready").respond_with_json({})
    httpserver.expect_request("/v1/meta").respond_with_json({ "version" => "1.36" })
    httpserver.expect_request("/v1/nodes").respond_with_json({ "nodes" => [{ "gitHash" => "ABC", "status" => "HEALTHY" }] })
  end

  # weaviate_no_auth_mock
  def no_auth_mock!
    httpserver.expect_request("/v1/.well-known/openid-configuration").respond_with_json({}, status: 404)
  end

  # weaviate_auth_mock
  def auth_mock!
    httpserver.expect_request("/v1/.well-known/openid-configuration")
              .respond_with_json({ "href" => "#{MockContext::MOCK_SERVER_URL}/endpoints", "clientId" => MockContext::CLIENT_ID })
    httpserver.expect_request("/endpoints").respond_with_json({ "token_endpoint" => "#{MockContext::MOCK_SERVER_URL}/auth" })
  end

  def connect_mock_client(**kwargs, &block)
    Weaviate.connect_to_local(host: MockContext::MOCK_IP, port: MockContext::MOCK_PORT,
                              grpc_port: MockContext::MOCK_PORT_GRPC, **kwargs, &block)
  end

  def grpc_impl(&block)
    MockGrpcServer.impl = Class.new(&block).new
  end
end
