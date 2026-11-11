# frozen_string_literal: true

require "set"

# Port of test/test_rbac.py
RSpec.describe "RBAC models" do
  let(:actions) { Weaviate::Classes::RBAC::Actions }
  let(:permissions) { Weaviate::Classes::RBAC::Permissions }

  it "test_permissions_roles_only_manage_false" do
    expect(permissions.roles(read: false, role: "*").length).to eq(0)
  end

  it "test_permissions_roles_only_manage_true" do
    perms = permissions.roles(read: true, role: "*")
    expect(perms.length).to eq(1)
    expect(perms[0].actions.length).to eq(1)
  end

  it "test_permissions_roles" do
    perms = permissions.roles(read: true, create: false, role: "*")
    expect(perms.length).to eq(1)
    expect(perms[0].actions.length).to eq(1)
  end

  it "test_permissions_backup_read" do
    perms = permissions.backup(collection: "books", read: true)
    expect(perms.map(&:to_weaviate)).to eq(
      [[{ "action" => "read_backups", "backups" => { "collection" => "Books" } }]]
    )
  end

  it "test_role_parses_read_backups" do
    role = Weaviate::RBAC::Models::Role.from_weaviate_role(
      { "name" => "r", "permissions" => [{ "action" => "read_backups", "backups" => { "collection" => "Books" } }] }
    )
    expect(role.backups_permissions[0].actions).to eq(Set[actions::Backups::READ])
  end

  it "joins permissions on the same resource" do
    role = Weaviate::RBAC::Models::Role.from_weaviate_role(
      { "name" => "r", "permissions" => [
        { "action" => "read_data", "data" => { "collection" => "Books", "tenant" => "*" } },
        { "action" => "update_data", "data" => { "collection" => "Books", "tenant" => "*" } },
        { "action" => "read_data", "data" => { "collection" => "Other" } },
        { "action" => "read_roles", "roles" => { "role" => "x", "scope" => "match" } },
        { "action" => "some_new_action" }
      ] }
    )
    expect(role.data_permissions.length).to eq(2)
    expect(role.data_permissions[0].actions).to eq(Set["read_data", "update_data"])
    expect(role.data_permissions[1].tenant).to eq("*")
    expect(role.roles_permissions[0].scope).to eq(Weaviate::Classes::RBAC::RoleScope::MATCH)
    expect(role.permissions.length).to eq(3)
  end

  it "builds the remaining permission shapes" do
    expect(permissions.alias(alias: "a", collection: "c", create: true).first.to_weaviate)
      .to eq([{ "action" => "create_aliases", "aliases" => { "alias" => "A", "collection" => "c" } }])
    expect(permissions.data(collection: %w[a b], tenant: %w[t1 t2], read: true).length).to eq(4)
    expect(permissions::Nodes.minimal(read: true).first.to_weaviate)
      .to eq([{ "action" => "read_nodes", "nodes" => { "collection" => "*", "verbosity" => "minimal" } }])
    expect(permissions::Groups.oidc(group: "g", read: true).first.to_weaviate)
      .to eq([{ "action" => "read_groups", "groups" => { "group" => "g", "groupType" => "oidc" } }])
    expect(permissions.roles(role: "r", read: true, scope: "all").first.to_weaviate)
      .to eq([{ "action" => "read_roles", "roles" => { "role" => "r", "scope" => "all" } }])
    expect(permissions.cluster(read: false)).to eq([])
    expect(permissions.mcp(read: true).first.to_weaviate).to eq([{ "action" => "read_mcp" }])
  end
end
