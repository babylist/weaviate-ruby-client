# frozen_string_literal: true

# Port of test/test_connection_params.py (grpc-web/Pyodide cases are out of scope for the Ruby client)
RSpec.describe Weaviate::Connect::ConnectionParams do
  it "test_same_host_port_raises" do
    expect do
      described_class.from_params(http_host: "localhost", http_port: 8090, http_secure: false,
                                  grpc_host: "localhost", grpc_port: 8090, grpc_secure: false)
    end.to raise_error(ArgumentError, /must be different/)
  end

  it "builds from url" do
    params = described_class.from_url("https://example.com", 50_051)
    expect(params.http.to_h).to eq(host: "example.com", port: 443, secure: true)
    expect(params.grpc.to_h).to eq(host: "example.com", port: 50_051, secure: true)
    expect(params.http_url).to eq("https://example.com:443")
  end

  it "rejects unsupported scheme" do
    expect { described_class.from_url("ftp://example.com", 1) }.to raise_error(ArgumentError, /Unsupported scheme/)
  end

  it "validates ports and hosts" do
    expect { Weaviate::Connect::ProtocolParams.new(host: "", port: 1, secure: false) }.to raise_error(ArgumentError)
    expect { Weaviate::Connect::ProtocolParams.new(host: "h", port: 70_000, secure: false) }.to raise_error(ArgumentError)
  end

  it "parses weaviate cloud cluster urls like the python helper" do
    expect(Weaviate::ConnectHelpers.parse_weaviate_cloud_cluster_url("abc.something.weaviate.cloud"))
      .to eq(["abc.something.weaviate.cloud", "grpc-abc.something.weaviate.cloud"])
    expect(Weaviate::ConnectHelpers.parse_weaviate_cloud_cluster_url("https://abc.weaviate.network"))
      .to eq(["abc.weaviate.network", "abc.grpc.weaviate.network"])
  end
end

# Port of test/test_auth.py
RSpec.describe Weaviate::Auth do
  [[-1, true], [5, false]].each do |expires_in, warning|
    it "test_bearer_validation expires_in=#{expires_in}" do
      _, warnings = Weaviate::Warnings.capture do
        Weaviate::Classes::Init::Auth.bearer_token("Doesn't matter", refresh_token: "Doesn't matter",
                                                                     expires_in: expires_in)
      end
      if warning
        expect(warnings.length).to eq(1)
        expect(warnings.first).to start_with("Auth003")
      else
        expect(warnings).to be_empty
      end
    end
  end
end

# Port of test/test_connect_helpers.py
RSpec.describe Weaviate::ConnectHelpers do
  it "test_connect_to_custom_accepts_string_api_key" do
    client = Weaviate::Client.new(
      connection_params: Weaviate::Connect::ConnectionParams.from_params(
        http_host: "localhost", http_port: 8080, http_secure: false,
        grpc_host: "localhost", grpc_port: 50_051, grpc_secure: false
      ),
      auth_client_secret: described_class.parse_auth_credentials("api-key")
    )
    auth = client.connection.instance_variable_get(:@auth)
    expect(auth).to be_a(Weaviate::Auth::APIKey)
    expect(auth.api_key).to eq("api-key")
  end

  it "rejects invalid credentials" do
    expect { described_class.parse_auth_credentials(123) }.to raise_error(ArgumentError, /Invalid auth credentials/)
  end
end
