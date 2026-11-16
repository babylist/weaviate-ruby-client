# frozen_string_literal: true

# Port of test/test_auth.py (async variants are out of scope for the Ruby client)
RSpec.describe Weaviate::Connect::Authentication do
  let(:oidc_config) { { "href" => "http://localhost:1234/.well-known", "clientId" => "client-id" } }
  let(:http) { instance_double(Weaviate::Connect::HTTPClient) }

  def response(body)
    Weaviate::Connect::HTTPResponse.new(200, JSON.generate(body), { "content-type" => "application/json" })
  end

  before do
    allow(http).to receive(:get).with(oidc_config["href"], timeout: described_class::AUTH_DEFAULT_TIMEOUT)
                                .and_return(response({ "token_endpoint" => "http://localhost:1234/token" }))
  end

  it "test_oidc_session_uses_connection_transports" do
    credentials = Weaviate::Auth.bearer_token("Doesn't matter", refresh_token: "Doesn't matter")
    allow(http).to receive(:post).and_return(response({ "access_token" => "new", "expires_in" => 60 }))

    session = described_class.new(oidc_config, credentials, http).auth_session
    session.refresh_token!

    expect(http).to have_received(:post).with("http://localhost:1234/token", hash_including(:form))
    expect(session.access_token).to eq("new")
  end
end
