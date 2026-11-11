# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_groups.py
RSpec.describe "groups", :integration do
  rbac_ports = [8092, 50_063]
  rbac_auth_creds = Weaviate::Auth.api_key("admin-key")

  it "test_assign_and_get_group_roles_oidc" do
    skip_if_native!("needs the RBAC instance from the docker-compose stack")
    client = client_factory(ports: rbac_ports, auth_credentials: rbac_auth_creds)
    skip_unless_version!(client, 1, 32, 0)

    roles_to_assign = %w[viewer admin]
    group_id = "/assign-group"
    client.groups.oidc.revoke_roles(group_id: group_id, role_names: roles_to_assign)

    roles_base = client.groups.oidc.get_assigned_roles(group_id: group_id)
    expect(roles_base.length).to eq(0)

    client.groups.oidc.assign_roles(group_id: group_id, role_names: roles_to_assign)

    roles = client.groups.oidc.get_assigned_roles(group_id: group_id, include_permissions: true)
    expect(roles.length).to eq(2)
    roles_to_assign.each do |role_name|
      expect(roles).to include(role_name)
      expect(roles[role_name]).to be_a(Weaviate::RBAC::Models::Role)
    end

    client.groups.oidc.revoke_roles(group_id: group_id, role_names: roles_to_assign)

    roles_base = client.groups.oidc.get_assigned_roles(group_id: group_id)
    expect(roles_base.length).to eq(0)
  end

  it "test_known_groups" do
    skip_if_native!("needs the RBAC instance from the docker-compose stack")
    client = client_factory(ports: rbac_ports, auth_credentials: rbac_auth_creds)
    skip_unless_version!(client, 1, 32, 0)

    group1 = "/known-group1"
    group2 = "/known-group2"
    client.groups.oidc.assign_roles(group_id: group1, role_names: "viewer")
    client.groups.oidc.assign_roles(group_id: group2, role_names: "viewer")

    groups = client.groups.oidc.get_known_group_names
    expect(groups.length).to be >= 2 # other tests may add groups
    expect(groups).to include(group1)
    expect(groups).to include(group2)

    client.groups.oidc.revoke_roles(group_id: group1, role_names: "viewer")
    client.groups.oidc.revoke_roles(group_id: group2, role_names: "viewer")

    groups = client.groups.oidc.get_known_group_names
    expect(groups.length).to be >= 0 # other tests may add groups
    expect(groups).not_to include(group1)
    expect(groups).not_to include(group2)
  end

  it "test_get_group_assignments" do
    skip_if_native!("needs the RBAC instance from the docker-compose stack")
    client = client_factory(ports: rbac_ports, auth_credentials: rbac_auth_creds)
    skip_unless_version!(client, 1, 32, 0)

    role_name = "test_group_assignments_role"
    client.roles.delete(role_name: role_name)
    client.roles.create(role_name: role_name, permissions: [])

    group_assignments = client.roles.get_group_assignments(role_name: role_name)
    expect(group_assignments.length).to eq(0)

    client.groups.oidc.assign_roles(group_id: "custom-group", role_names: role_name)
    client.groups.oidc.assign_roles(group_id: "custom-group2", role_names: role_name)

    group_assignments = client.roles.get_group_assignments(role_name: role_name)
    expect(group_assignments.length).to eq(2)
    group_assignments.each do |group|
      expect(%w[custom-group custom-group2]).to include(group.group_id)
      expect(group.group_type).to eq(Weaviate::RBAC::Models::GroupTypes::OIDC)
    end

    client.groups.oidc.revoke_roles(group_id: "custom-group", role_names: role_name)
    client.groups.oidc.revoke_roles(group_id: "custom-group2", role_names: role_name)
  end
end
