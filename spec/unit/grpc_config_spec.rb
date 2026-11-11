# frozen_string_literal: true

# Port of mock_tests/test_grpc_config.py
RSpec.describe "gRPC channel configuration" do
  let(:secure_params) do
    Weaviate::Connect::ConnectionParams.new(
      http: Weaviate::Connect::ProtocolParams.new(host: "localhost", port: 8080, secure: false),
      grpc: Weaviate::Connect::ProtocolParams.new(host: "localhost", port: 50_051, secure: true)
    )
  end
  let(:insecure_params) do
    Weaviate::Connect::ConnectionParams.new(
      http: Weaviate::Connect::ProtocolParams.new(host: "localhost", port: 8080, secure: false),
      grpc: Weaviate::Connect::ProtocolParams.new(host: "localhost", port: 50_051, secure: false)
    )
  end

  it "test_grpc_config_channel_options" do
    opts = [["grpc.ssl_target_name_override", "my-host"]]
    expect(Weaviate::Config::GrpcConfig.new(channel_options: opts).channel_options).to eq(opts)
  end

  it "test_secure_channel_default_credentials" do
    creds = secure_params.grpc_channel_credentials
    expect(creds).to be_a(GRPC::Core::ChannelCredentials)
  end

  it "test_secure_channel_roots_file_env_overrides_bundle" do
    allow(GRPC::Core::ChannelCredentials).to receive(:new).and_return(:creds)
    ENV["GRPC_DEFAULT_SSL_ROOTS_FILE_PATH"] = "/etc/ssl/corp-roots.pem"
    secure_params.grpc_channel_credentials
    expect(GRPC::Core::ChannelCredentials).to have_received(:new).with(no_args)
  ensure
    ENV.delete("GRPC_DEFAULT_SSL_ROOTS_FILE_PATH")
  end

  it "test_insecure_channel_no_config" do
    expect(insecure_params.grpc_channel_credentials).to eq(:this_channel_is_insecure)
  end

  it "test_channel_options_appended_secure" do
    config = Weaviate::Config::GrpcConfig.new(channel_options: [["grpc.ssl_target_name_override", "my-gateway.example.com"]])
    args = secure_params.grpc_channel_args(grpc_config: config)
    expect(args["grpc.ssl_target_name_override"]).to eq("my-gateway.example.com")
  end

  it "test_channel_options_appended_insecure" do
    config = Weaviate::Config::GrpcConfig.new(channel_options: [["grpc.keepalive_time_ms", 30_000]])
    args = insecure_params.grpc_channel_args(grpc_config: config)
    expect(args["grpc.keepalive_time_ms"]).to eq(30_000)
  end

  it "test_credentials" do
    creds = GRPC::Core::ChannelCredentials.new
    config = Weaviate::Config::GrpcConfig.new(credentials: creds)
    expect(secure_params.grpc_channel_credentials(grpc_config: config)).to be(creds)
  end

  it "builds a stub from the params" do
    stub = insecure_params.grpc_stub(Weaviate::V1::WeaviateService::Stub)
    expect(stub).to be_a(Weaviate::V1::WeaviateService::Stub)
  end
end
