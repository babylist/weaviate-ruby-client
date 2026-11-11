# frozen_string_literal: true

require "net/http"
require "json"

# Port of weaviate-python-client/integration/test_auth.py.
#
# Every test except test_client_with_authentication_with_anon_weaviate needs one of the
# docker-compose auth instances (okta on 8082/8083, WCS-style API keys on 8085) and is skipped
# in native mode; the OIDC tests additionally need OKTA_*/WCS_* secrets, as in Python.
module Batch5Specs
  RSpec.describe "auth", :integration do
    include Batch5Helpers

    # ANON_PORT (8080) is the default instance (WEAVIATE_PORT).
    okta_port_cc = 8082
    okta_port_users = 8083
    wcs_port = 8085
    wcs_port_grpc = 50_056

    let(:anon_port) { default_port }
    let(:okta_port_cc) { okta_port_cc }
    let(:okta_port_users) { okta_port_users }
    let(:wcs_port) { wcs_port }
    let(:wcs_port_grpc) { wcs_port_grpc }

    def skip_unless_auth_instance!(port)
      skip_if_native!("needs the docker-compose auth instance on port #{port}")
    end

    # Send a request, retrying with backoff on transport errors or 429.
    def request_with_backoff
      [2, 4, 8].each do |delay|
        begin
          response = yield
        rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout
          sleep(delay)
          next
        end
        return response unless response.code.to_i == 429

        sleep(delay)
      end
      yield
    end

    # Get an access token with the user and pw from the token issuer of the Weaviate at +url+.
    def get_access_token(url, user, pw)
      weaviate_open_id_config = Net::HTTP.get_response(URI("http://#{url}/v1/.well-known/openid-configuration"))
      response_json = JSON.parse(weaviate_open_id_config.body)
      client_id = response_json["clientId"]
      href = response_json["href"]

      response_auth = request_with_backoff { Net::HTTP.get_response(URI(href)) }
      auth_body = {
        "grant_type" => "password", "client_id" => client_id, "username" => user, "password" => pw,
        "scope" => "openid offline_access"
      }
      token_endpoint = JSON.parse(response_auth.body)["token_endpoint"]
      response_post = request_with_backoff { Net::HTTP.post_form(URI(token_endpoint), auth_body) }
      expect(response_post.code.to_i).to eq(200)
      JSON.parse(response_post.body)
    end

    it "test_no_auth_provided" do
      # Exception when trying to access a weaviate that requires authentication.
      skip_unless_auth_instance!(okta_port_cc)
      expect(is_auth_enabled("localhost:#{okta_port_cc}")).to be true
      expect do
        Weaviate.connect_to_local(port: okta_port_cc)
      end.to raise_error(Weaviate::Exceptions::AuthenticationFailedError)
    end

    [["okta", "OKTA_CLIENT_SECRET", okta_port_cc, "some_scope"]].each do |name, env_variable_name, port, scope|
      it "test_authentication_client_credentials[#{name}-#{env_variable_name}-#{port}-#{scope}]" do
        # Client credential flow with various providers.
        client_secret = ENV.fetch(env_variable_name, nil)
        skip("No #{name} login data found.") if client_secret.nil?
        skip_unless_auth_instance!(port)

        expect(is_auth_enabled("localhost:#{port}")).to be true
        Weaviate.connect_to_local(
          port: port, auth_credentials: Weaviate::Classes::Init::Auth.client_credentials(client_secret, scope: scope)
        ) do |client|
          client.collections.list_all # no exception
        end
      end
    end

    [
      # WCS keycloak times out too often
      ["WCS", "oidc-test-user@weaviate.io", "WCS_DUMMY_CI_PW", wcs_port, nil, false],
      ["okta", "test@test.de", "OKTA_DUMMY_CI_PW", okta_port_users, "some_scope offline_access", false],
      ["okta - no refresh", "test@test.de", "OKTA_DUMMY_CI_PW", okta_port_users, "some_scope", true]
    ].each do |name, user, env_variable_name, port, scope, warning|
      it "test_authentication_user_pw[#{name}-#{user}-#{env_variable_name}-#{port}-#{scope}-#{warning}]" do
        # Resource Owner Password Credentials Grant (User + PW).
        skip_unless_auth_instance!(port)
        expect(is_auth_enabled("localhost:#{port}")).to be true

        pw = ENV.fetch(env_variable_name, nil)
        skip("No login data for #{name} found.") if pw.nil?

        auth = Weaviate::Classes::Init::Auth.client_password(user, pw, scope: scope)
        warnings = capture_warnings do
          Weaviate.connect_to_local(port: port, auth_credentials: auth) do |client|
            client.collections.list_all # no exception
          end
        end

        if warning
          expect(warnings.length).to eq(1)
          expect(warnings[0]).to start_with("Auth002")
        else
          expect(warnings).to eq([])
        end
      end
    end

    it "test_client_with_authentication_with_anon_weaviate" do
      # Warn users when their client has auth enabled, but weaviate has only anon access.
      expect(is_auth_enabled("localhost:#{anon_port}")).to be false

      auth = Weaviate::Classes::Init::Auth.client_password("someUser", "SomePw")
      warnings = capture_warnings do
        connect_to_default_local(auth_credentials: auth) do |client|
          client.collections.list_all
        end
      end
      expect(warnings.length).to eq(1)
      expect(warnings.any? { |w| w.start_with?("Auth001") }).to be true
    end

    [
      # WCS keycloak times out too often
      ["WCS", "oidc-test-user@weaviate.io", "WCS_DUMMY_CI_PW", wcs_port],
      ["okta", "test@test.de", "OKTA_DUMMY_CI_PW", okta_port_users]
    ].each do |name, user, env_variable_name, port|
      it "test_authentication_with_bearer_token[#{name}-#{user}-#{env_variable_name}-#{port}]" do
        # Authentication using existing bearer token.
        skip_unless_auth_instance!(port)
        url = "localhost:#{port}"
        expect(is_auth_enabled(url)).to be true
        pw = ENV.fetch(env_variable_name, nil)
        skip("No login data for #{name} found.") if pw.nil?

        token = get_access_token(url, user, pw)
        auth = Weaviate::Classes::Init::Auth.bearer_token(
          token["access_token"], expires_in: Integer(token["expires_in"]), refresh_token: token["refresh_token"]
        )
        Weaviate.connect_to_local(port: port, auth_credentials: auth) do |client|
          client.collections.exists("something")
        end
      end
    end

    it "test_authentication_with_bearer_token_no_refresh" do
      skip_unless_auth_instance!(okta_port_users)
      url = "localhost:#{okta_port_users}"
      expect(is_auth_enabled(url)).to be true
      pw = ENV.fetch("OKTA_DUMMY_CI_PW", nil)
      skip("No login data for found.") if pw.nil?

      token = get_access_token(url, "test@test.de", pw)
      auth = Weaviate::Classes::Init::Auth.bearer_token(token["access_token"],
                                                        expires_in: Integer(token["expires_in"]))
      warnings = capture_warnings do
        Weaviate.connect_to_local(port: okta_port_users, auth_credentials: auth) do |client|
          client.collections.list_all
        end
      end
      expect(warnings.length).to eq(1)
      expect(warnings[0]).to start_with("Auth002")
    end

    it "test_api_key_string" do
      skip_unless_auth_instance!(wcs_port)
      expect(is_auth_enabled("localhost:#{wcs_port}")).to be true
      Weaviate.connect_to_local(port: wcs_port, auth_credentials: "my-secret-key") do |client|
        client.collections.list_all
      end
    end

    it "test_api_key" do
      skip_unless_auth_instance!(wcs_port)
      expect(is_auth_enabled("localhost:#{wcs_port}")).to be true
      Weaviate.connect_to_local(port: wcs_port,
                                auth_credentials: Weaviate::Classes::Init::Auth.api_key("my-secret-key")) do |client|
        client.collections.list_all
      end
    end

    # Python parametrizes over [None, grpc.ssl_channel_credentials()]; built lazily (needs grpc loaded).
    [["creds0", -> {}], ["creds1", -> { GRPC::Core::ChannelCredentials.new }]].each do |id, make_creds|
      it "test_custom_grpc_credentials[#{id}]" do
        skip_unless_auth_instance!(wcs_port)
        expect(is_auth_enabled("localhost:#{wcs_port}")).to be true
        Weaviate.connect_to_local(
          port: wcs_port, grpc_port: wcs_port_grpc,
          auth_credentials: Weaviate::Classes::Init::Auth.api_key("my-secret-key"),
          additional_config: Weaviate::Classes::Init::AdditionalConfig.new(
            grpc_config: Weaviate::Classes::Init::GrpcConfig.new(credentials: make_creds.call)
          )
        ) do |client|
          expect(client.is_live).to be true
        end
      end
    end

    %w[Authorization authorization].each do |header_name|
      it "test_api_key_in_header[#{header_name}]" do
        skip_unless_auth_instance!(wcs_port)
        expect(is_auth_enabled("localhost:#{wcs_port}")).to be true
        Weaviate.connect_to_local(port: wcs_port, headers: { header_name => "Bearer my-secret-key" }) do |client|
          client.collections.list_all
        end
      end
    end

    it "test_api_key_wrong_key" do
      skip_unless_auth_instance!(wcs_port)
      expect(is_auth_enabled("localhost:#{wcs_port}")).to be true

      expect do
        Weaviate.connect_to_local(port: wcs_port,
                                  auth_credentials: Weaviate::Classes::Init::Auth.api_key("my-secret-key-wrong"))
      end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError) { |e| expect(e.status_code).to eq(401) }
    end

    it "test_auth_e2e" do
      skip_unless_auth_instance!(wcs_port)
      name = sanitize_name(node_name)
      url = "localhost:#{wcs_port}"
      expect(is_auth_enabled(url)).to be true

      Weaviate.connect_to_local(
        port: wcs_port, grpc_port: wcs_port_grpc,
        auth_credentials: Weaviate::Classes::Init::Auth.api_key("my-secret-key")
      ) do |client|
        client.collections.delete(name)
        col = client.collections.create(
          name,
          description: "test",
          properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)],
          vectorizer_config: Config::Configure::Vectorizer.none
        )
        col.data.insert({ "name" => "test" })
        col.data.insert_many([{ "name" => "test2" }])
        expect(col.query.fetch_objects.objects.length).to eq(2)

        col.data.delete_many(Query::Filter.by_property("name").equal("test"))
        expect(col.query.fetch_objects.objects.length).to eq(1)
      end
    end
  end
end
