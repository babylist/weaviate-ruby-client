# frozen_string_literal: true

# Port of mock_tests/test_roles.py
RSpec.describe "roles (mock)" do
  include_context "mock weaviate"

  [true, false].each do |answer|
    it "test_has_permissions[#{answer}]" do
      no_auth_mock!
      httpserver.expect_request("/v1/authz/roles/reader/has-permission", method: "POST").respond_with_json(answer)
      client = connect_mock_client
      permissions = Weaviate::Classes::RBAC::Permissions.collections(collection: "Books", read_config: true)
      expect(client.roles.has_permissions(permissions: permissions, role: "reader")).to be(answer)
    ensure
      client&.close
    end
  end

  it "creates roles and parses list_all" do
    no_auth_mock!
    httpserver.expect_request(
      "/v1/authz/roles", method: "POST",
                         json: { "name" => "r", "permissions" => [{ "action" => "read_data",
                                                                    "data" => { "collection" => "Books", "tenant" => "*" } }] }
    ).respond_with_json({}, status: 201)
    httpserver.expect_request("/v1/authz/roles", method: "GET").respond_with_json(
      [{ "name" => "r", "permissions" => [{ "action" => "read_cluster" }] }]
    )
    httpserver.expect_request("/v1/authz/roles/missing", method: "GET").respond_with_json({}, status: 404)
    client = connect_mock_client
    role = client.roles.create(role_name: "r",
                               permissions: Weaviate::Classes::RBAC::Permissions.data(collection: "books", read: true))
    expect(role.data_permissions.first.collection).to eq("Books")
    expect(client.roles.list_all["r"].cluster_permissions.first.actions).to eq(Set["read_cluster"])
    expect(client.roles.get("missing")).to be_nil
    expect(client.roles.exists(role_name: "missing")).to be(false)
  ensure
    client&.close
  end
end
