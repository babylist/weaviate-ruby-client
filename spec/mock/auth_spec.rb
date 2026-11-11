# frozen_string_literal: true

# Port of mock_tests/test_auth.py (async variants are out of scope for the Ruby client)
RSpec.describe "authentication against a mock Weaviate" do
  include_context "mock weaviate"

  access_token = "HELLO!IamAnAccessToken"
  client_secret = "SomeSecret.DontTell"
  scope = "IcanBeAnything"
  refresh_token = "UseMeToRefreshYourAccessToken"
  client_id = MockContext::CLIENT_ID

  def refresh_threads
    Thread.list.select { |t| t.name == "TokenRefresh" && t.alive? }
  end

  before { auth_mock! }

  it "test_user_password" do
    user = "AUsername"
    pw = "SomePassWord"
    httpserver.expect_request("/auth", data: "grant_type=password&username=#{user}&password=#{pw}&client_id=#{client_id}")
              .respond_with_json({ "access_token" => access_token, "expires_in" => 500, "refresh_token" => refresh_token })
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    connect_mock_client(auth_credentials: Weaviate::Auth::AuthClientPassword.new(username: user, password: pw)) do |client|
      client.collections.list_all
    end
    httpserver.check_assertions
  end

  it "test_bearer_token" do
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: refresh_token)) do |client|
      client.collections.list_all
    end
    httpserver.check_assertions
  end

  it "test_client_credentials" do
    httpserver.expect_request("/auth").respond_with_json({ "access_token" => access_token, "expires_in" => 500 })
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    connect_mock_client(auth_credentials: Weaviate::Auth.client_credentials(client_secret, scope: scope)) do |client|
      client.collections.list_all
    end
    httpserver.check_assertions
  end

  it "test_client_credentials_refresh" do
    token_requests = 0
    httpserver.expect_request("/auth").respond_with_handler do |_req|
      token_requests += 1
      [200, { "content-type" => "application/json" }, JSON.generate({ "access_token" => access_token, "expires_in" => 1 })]
    end
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    connect_mock_client(auth_credentials: Weaviate::Auth.client_credentials(client_secret, scope: scope)) do |client|
      client.collections.list_all
      first = token_requests
      sleep 3
      expect(token_requests).to be > first
    end
  end

  it "test_token_refresh_survives_failures" do
    hits = []
    httpserver.expect_request("/auth").respond_with_handler do |_req|
      hits << Time.now
      [400, { "content-type" => "application/json" },
       JSON.generate({ "error" => "invalid_grant", "error_description" => "refresh token expired" })]
    end
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    before_threads = refresh_threads
    _, warnings = Weaviate::Warnings.capture do
      connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: refresh_token,
                                                                                       expires_in: 1)) do |client|
        refreshers = refresh_threads - before_threads
        expect(refreshers.length).to eq(1)
        sleep 3
        expect(refreshers.first).to be_alive
        client.collections.list_all
      end
    end
    expect(hits.length).to be >= 2
    expect(warnings.count { |w| w.start_with?("Con001") }).to be >= 1
    expect(refresh_threads - before_threads).to be_empty
  end

  it "test_sync_reconnect_leaves_exactly_one_refresher_thread" do
    httpserver.expect_request("/auth")
              .respond_with_json({ "access_token" => access_token, "expires_in" => 500, "refresh_token" => refresh_token })
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    before_threads = refresh_threads
    client = connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: refresh_token,
                                                                                               expires_in: 500))
    first = refresh_threads - before_threads
    expect(first.length).to eq(1)
    client.close
    first.first.join(2)
    expect(first.first).not_to be_alive
    client.connect
    client.collections.list_all
    alive = refresh_threads - before_threads
    expect(alive.length).to eq(1)
    expect(alive.first).not_to be(first.first)
    client.close
    alive.first.join(2)
    expect(alive.first).not_to be_alive
  end

  %w[Authorization authorization].each do |header_name|
    it "test_auth_header_priority #{header_name}" do
      httpserver.expect_request("/auth")
                .respond_with_json({ "access_token" => access_token, "expires_in" => 500, "refresh_token" => refresh_token })
      seen = nil
      httpserver.expect_request("/v1/schema").respond_with_handler do |req|
        seen = req.headers["authorization"]
        [200, { "content-type" => "application/json" }, JSON.generate({ "classes" => [] })]
      end
      _, warnings = Weaviate::Warnings.capture do
        connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: "SOMETHING"),
                            headers: { header_name => "Bearer OTHER TOKEN" }) do |client|
          client.collections.list_all
        end
      end
      expect(seen).to eq("Bearer #{access_token}")
      httpserver.check_assertions
      expect(warnings.count { |w| w.start_with?("Auth004") }).to eq(1)
    end
  end

  it "test_refresh" do
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    httpserver.expect_request("/auth", data: "grant_type=refresh_token&refresh_token=#{refresh_token}&client_id=#{client_id}")
              .respond_with_json({ "access_token" => access_token, "expires_in" => 1,
                                   "refresh_token" => refresh_token + Time.now.to_f.to_s })
    connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: refresh_token,
                                                                                     expires_in: 1)) do |client|
      client.collections.list_all
    end
    httpserver.check_assertions
  end

  it "test_refresh_of_refresh" do
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}" })
              .respond_with_json({ "classes" => [] })
    refresh_calls = 0
    failures = []
    httpserver.expect_request("/auth").respond_with_handler do |req|
      failures << req.body unless req.body.include?("refresh_token=#{refresh_token}#{refresh_calls}")
      refresh_calls += 1
      [200, { "content-type" => "application/json" },
       JSON.generate({ "access_token" => access_token, "expires_in" => 1,
                       "refresh_token" => refresh_token + refresh_calls.to_s })]
    end
    connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: "#{refresh_token}0",
                                                                                     expires_in: 1)) do |client|
      sleep 5
      client.collections.list_all
    end
    expect(refresh_calls).to be > 1
    expect(failures).to be_empty
    httpserver.check_assertions
  end

  it "test_missing_scope" do
    expect do
      connect_mock_client(auth_credentials: Weaviate::Auth.client_credentials(client_secret))
    end.to raise_error(Weaviate::Exceptions::MissingScopeError)
  end

  it "test_token_refresh_timeout" do
    first_request = true
    httpserver.expect_request("/auth").respond_with_handler do |_req|
      if first_request
        first_request = false
        sleep 6 # auth requests time out after 5s
      end
      [200, { "content-type" => "application/json" },
       JSON.generate({ "access_token" => "#{access_token}_1", "expires_in" => 31 })]
    end
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer #{access_token}_1" })
              .respond_with_json({ "classes" => [] })
    _, warnings = Weaviate::Warnings.capture do
      connect_mock_client(auth_credentials: Weaviate::Auth.bearer_token(access_token, refresh_token: refresh_token,
                                                                                       expires_in: 1)) do |client|
        sleep 9
        client.collections.list_all
      end
    end
    httpserver.check_assertions
    expect(warnings.count { |w| w.start_with?("Con001") }).to eq(1)
  end
end

RSpec.describe "authentication without OIDC" do
  include_context "mock weaviate"

  it "test_auth_header_without_weaviate_auth" do
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer OTHER TOKEN" })
              .respond_with_json({ "classes" => [] })
    connect_mock_client(headers: { "Authorization" => "Bearer OTHER TOKEN" }) { |client| client.collections.list_all }
    httpserver.check_assertions
  end

  it "test_auth_header_with_catchall_proxy" do
    httpserver.expect_request("/v1/schema").respond_with_json({ "classes" => [] })
    httpserver.expect_request("/v1/.well-known/openid-configuration").respond_with_data("JsonCannotParseThis")
    _, warnings = Weaviate::Warnings.capture do
      connect_mock_client(auth_credentials: Weaviate::Auth.client_password("test-username", "test-password")) do |client|
        client.collections.list_all
      end
    end
    httpserver.check_assertions
    expect(warnings.count { |w| w.start_with?("Auth005") }).to eq(1)
  end

  ["Super-secret-key", Weaviate::Auth::AuthApiKey.new(api_key: "Super-secret-key")].each do |api_key|
    it "test_with_simple_auth_no_oidc_via_api_key #{api_key.class}" do
      httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer Super-secret-key" })
                .respond_with_json({ "classes" => [] })
      _, warnings = Weaviate::Warnings.capture do
        client = connect_mock_client(auth_credentials: api_key)
        client.collections.list_all
        client.close
      end
      httpserver.check_assertions
      expect(warnings.select { |w| w.start_with?("Auth", "Con") }).to be_empty
    end
  end

  it "test_with_simple_auth_no_oidc_via_additional_headers" do
    httpserver.expect_request("/v1/schema", headers: { "Authorization" => "Bearer Super-secret-key" })
              .respond_with_json({ "classes" => [] })
    _, warnings = Weaviate::Warnings.capture do
      connect_mock_client(headers: { "Authorization" => "Bearer Super-secret-key" }) { |c| c.collections.list_all }
    end
    httpserver.check_assertions
    expect(warnings.select { |w| w.start_with?("Auth", "Con") }).to be_empty
  end
end
