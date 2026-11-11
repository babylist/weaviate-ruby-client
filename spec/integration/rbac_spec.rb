# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_rbac.py.
#
# Every test needs the RBAC docker-compose instance on (8092, 50063) with the "admin-key" API key;
# they are skipped in native mode (client_factory skips non-default ports).
module Batch5Specs
  RSpec.describe "rbac", :integration do
    include Batch5Helpers

    rbac_ports = [8092, 50_063]
    actions = RBAC::Actions
    permissions = RBAC::Permissions

    let(:rbac_ports) { rbac_ports }

    def rbac_client
      client_factory(ports: rbac_ports, auth_credentials: Batch5Helpers::RBAC_AUTH_CREDS)
    end

    def version_lower_than?(client, major, minor, patch)
      client.connection.weaviate_version.is_lower_than(major, minor, patch)
    end

    # Python's Role(...) with every unspecified *_permissions list empty (the Ruby defaults).
    build_role = ->(name, **perms) { Models::Role.new(name: name, **perms) }

    # [id, permissions, expected role, min_version] - built lazily so nothing runs at load time.
    create_role_cases = [
      lambda {
        [permissions.backup(collection: "Test", manage: true),
         build_role.call("ManageAllBackups", backups_permissions: [
                     Models::BackupsPermissionOutput.new(collection: "Test", actions: [actions::Backups::MANAGE])
                   ]),
         nil]
      },
      lambda {
        [permissions.backup(collection: "Test", read: true),
         build_role.call("ReadBackups", backups_permissions: [
                     Models::BackupsPermissionOutput.new(collection: "Test", actions: [actions::Backups::READ])
                   ]),
         40]
      },
      lambda {
        [permissions.cluster(read: true),
         build_role.call("ReadCluster",
                   cluster_permissions: [Models::ClusterPermissionOutput.new(actions: [actions::Cluster::READ])]),
         nil]
      },
      lambda {
        [permissions.collections(collection: "Test", create_collection: true),
         build_role.call("CreateAllCollections", collections_permissions: [
                     Models::CollectionsPermissionOutput.new(collection: "Test", actions: [actions::Collections::CREATE])
                   ]),
         nil]
      },
      lambda {
        [permissions.data(collection: "*", create: true),
         build_role.call("CreateAllData", data_permissions: [
                     Models::DataPermissionOutput.new(collection: "*", tenant: "*", actions: [actions::Data::CREATE])
                   ]),
         nil]
      },
      lambda {
        [permissions.data(collection: %w[ColA ColB], tenant: %w[tenant1 tenant2], create: true),
         build_role.call("CreateDataInColsAndTenants", data_permissions: [
                     Models::DataPermissionOutput.new(collection: "ColA", tenant: "tenant1", actions: [actions::Data::CREATE]),
                     Models::DataPermissionOutput.new(collection: "ColA", tenant: "tenant2", actions: [actions::Data::CREATE]),
                     Models::DataPermissionOutput.new(collection: "ColB", tenant: "tenant1", actions: [actions::Data::CREATE]),
                     Models::DataPermissionOutput.new(collection: "ColB", tenant: "tenant2", actions: [actions::Data::CREATE])
                   ]),
         nil]
      },
      lambda {
        [permissions::Nodes.verbose(collection: "Test", read: true),
         build_role.call("VerboseNodes", nodes_permissions: [
                     Models::NodesPermissionOutput.new(verbosity: "verbose", actions: [actions::Nodes::READ],
                                                       collection: "Test")
                   ]),
         nil]
      },
      lambda {
        [permissions::Nodes.minimal(read: true),
         build_role.call("MinimalNodes", nodes_permissions: [
                     Models::NodesPermissionOutput.new(verbosity: "minimal", actions: [actions::Nodes::READ],
                                                       collection: "*")
                   ]),
         nil]
      },
      lambda {
        [permissions.roles(role: "*", create: true),
         build_role.call("ManageAllRoles", roles_permissions: [
                     Models::RolesPermissionOutput.new(role: "*", actions: [actions::Roles::CREATE],
                                                       scope: RBAC::RoleScope::MATCH)
                   ]),
         nil]
      },
      lambda {
        [permissions.tenants(collection: "*", read: true, update: true),
         build_role.call("TenantsReadRole", tenants_permissions: [
                     Models::TenantsPermissionOutput.new(collection: "*", tenant: "*",
                                                         actions: [actions::Tenants::READ, actions::Tenants::UPDATE])
                   ]),
         nil]
      },
      lambda {
        tenant_actions = [actions::Tenants::READ, actions::Tenants::UPDATE]
        [permissions.tenants(collection: %w[ColA ColB], tenant: %w[tenant1 tenant2], read: true, update: true),
         build_role.call("ReadSpecificTenantsInCols", tenants_permissions: [
                     Models::TenantsPermissionOutput.new(collection: "ColA", tenant: "tenant1", actions: tenant_actions),
                     Models::TenantsPermissionOutput.new(collection: "ColA", tenant: "tenant2", actions: tenant_actions),
                     Models::TenantsPermissionOutput.new(collection: "ColB", tenant: "tenant1", actions: tenant_actions),
                     Models::TenantsPermissionOutput.new(collection: "ColB", tenant: "tenant2", actions: tenant_actions)
                   ]),
         nil]
      },
      lambda {
        [permissions.users(user: "*", assign_and_revoke: true, read: true),
         build_role.call("UserAssignRole", users_permissions: [
                     Models::UsersPermissionOutput.new(users: "*",
                                                       actions: [actions::Users::ASSIGN_AND_REVOKE, actions::Users::READ])
                   ]),
         nil]
      },
      lambda {
        replicate_actions = [actions::Replicate::READ, actions::Replicate::UPDATE]
        [permissions.replicate(collection: %w[ColA ColB], shard: %w[tenant1 tenant2], read: true, update: true),
         build_role.call("Replicate", replicate_permissions: [
                     Models::ReplicatePermissionOutput.new(collection: "ColA", shard: "tenant1", actions: replicate_actions),
                     Models::ReplicatePermissionOutput.new(collection: "ColA", shard: "tenant2", actions: replicate_actions),
                     Models::ReplicatePermissionOutput.new(collection: "ColB", shard: "tenant1", actions: replicate_actions),
                     Models::ReplicatePermissionOutput.new(collection: "ColB", shard: "tenant2", actions: replicate_actions)
                   ]),
         32]
      },
      lambda {
        [permissions.alias(alias: "*", collection: "*", read: true, delete: true),
         build_role.call("AlliasRole", alias_permissions: [
                     Models::AliasPermissionOutput.new(alias: "*", collection: "*",
                                                       actions: [actions::Alias::READ, actions::Alias::DELETE])
                   ]),
         32] # Minimum version for alias permissions
      },
      lambda {
        [permissions.alias(alias: "myCAR", collection: "*", read: true, delete: true),
         build_role.call("AlliasRole3", alias_permissions: [
                     Models::AliasPermissionOutput.new(alias: "MyCAR", # capitalized the first letter.
                                                       collection: "*",
                                                       actions: [actions::Alias::READ, actions::Alias::DELETE])
                   ]),
         32] # Minimum version for alias permissions
      },
      lambda {
        [permissions.mcp(create: true, read: true, update: true),
         build_role.call("MCPAll", mcp_permissions: [
                     Models::MCPPermissionOutput.new(actions: [actions::MCP::CREATE, actions::MCP::READ,
                                                               actions::MCP::UPDATE])
                   ]),
         37] # Minimum version for MCP permissions
      },
      lambda {
        [permissions.mcp(read: true),
         build_role.call("MCPRead", mcp_permissions: [Models::MCPPermissionOutput.new(actions: [actions::MCP::READ])]),
         37] # Minimum version for MCP permissions
      },
      lambda {
        [permissions::Groups.oidc(group: "MyGroup", read: true),
         build_role.call("GroupRole", groups_permissions: [
                     Models::GroupsPermissionOutput.new(group: "MyGroup", group_type: "oidc",
                                                        actions: [actions::Groups::READ])
                   ]),
         32] # Minimum version for group permissions
      }
    ]

    create_role_cases.each_with_index do |make_case, i|
      it "test_create_role[permissions#{i}-expected#{i}-min_version#{i}]" do
        perms, expected, min_version = make_case.call
        client = rbac_client
        skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
        if !min_version.nil? && version_lower_than?(client, 1, min_version, 0)
          skip("This test requires Weaviate 1.#{min_version}.0 or higher")
        end

        begin
          client.roles.delete(expected.name)
          client.roles.create(role_name: expected.name, permissions: perms)
          role = client.roles.get(expected.name)
          expect(role).not_to be_nil
          expect(role).to eq(expected)
        ensure
          client.roles.delete(expected.name)
        end
      end
    end

    it "test_create_role_with_empty_alias" do
      client = rbac_client
      version = client.connection.weaviate_version
      skip("Alias permissions require Weaviate 1.32.0 or higher") if version.is_lower_than(1, 32, 0)

      role_name = "AlliasRole2"
      perms = RBAC::Permissions.alias(alias: "", collection: "*", read: true, delete: true)
      begin
        client.roles.delete(role_name)

        # Weaviate PR #13324 applies the collection-name rule to alias patterns, so these
        # releases reject an empty alias; older servers store it as "*". Match only "alias"
        # so a rewording of the server's message does not fail the test.
        if version.is_at_least_any([1, 38, 19], [1, 39, 10], [1, 40, 0])
          expect do
            client.roles.create(role_name: role_name, permissions: perms)
          end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError, /alias/)
          next
        end

        client.roles.create(role_name: role_name, permissions: perms)
        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role).to eq(
          Models::Role.new(
            name: role_name,
            alias_permissions: [
              Models::AliasPermissionOutput.new(alias: "*", collection: "*",
                                                actions: [RBAC::Actions::Alias::READ, RBAC::Actions::Alias::DELETE])
            ]
          )
        )
      ensure
        client.roles.delete(role_name)
      end
    end

    it "test_add_permissions_to_existing" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      role_name = "ExistingRolePermissionsAdd"
      client.roles.delete(role_name)
      begin
        client.roles.create(role_name: role_name,
                            permissions: RBAC::Permissions.collections(collection: "*", create_collection: true))
        role = client.roles.get(role_name)

        expect(role).not_to be_nil
        expect(role.collections_permissions).not_to be_nil
        expect(role.collections_permissions.length).to eq(1)
        expect(role.permissions.length).to eq(1)
        expect(role.collections_permissions[0].actions).to eq(Set[RBAC::Actions::Collections::CREATE])

        client.roles.add_permissions(
          permissions: [RBAC::Permissions.collections(collection: "*", delete_collection: true)],
          role_name: role_name
        )

        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role.collections_permissions).not_to be_nil
        expect(role.collections_permissions.length).to eq(1)
        expect(role.permissions.length).to eq(1)
        expect(role.collections_permissions[0].actions).to eq(
          Set[RBAC::Actions::Collections::CREATE, RBAC::Actions::Collections::DELETE]
        )
      ensure
        client.roles.delete(role_name)
      end
    end

    it "test_remove_permissions_from_existing" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      role_name = "ExistingRolePermissionsRemove"
      client.roles.delete(role_name)
      begin
        client.roles.create(
          role_name: role_name,
          permissions: RBAC::Permissions.collections(collection: "*", create_collection: true, delete_collection: true)
        )
        role = client.roles.get(role_name)

        expect(role).not_to be_nil
        expect(role.collections_permissions).not_to be_nil
        expect(role.collections_permissions.length).to eq(1)
        expect(role.collections_permissions[0].actions.length).to eq(2)
        expect(role.permissions.length).to eq(1)

        client.roles.remove_permissions(
          permissions: [RBAC::Permissions.collections(collection: "*", delete_collection: true)],
          role_name: role_name
        )

        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role.collections_permissions).not_to be_nil
        expect(role.collections_permissions.length).to eq(1)
        expect(role.permissions.length).to eq(1)
        expect(role.collections_permissions[0].actions).to eq(Set[RBAC::Actions::Collections::CREATE])
      ensure
        client.roles.delete(role_name)
      end
    end

    it "test_multiple_permissions" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      role_name = "MultiplePermissions"
      begin
        required_permissions = [
          RBAC::Permissions.data(collection: "test", create: true, update: true),
          RBAC::Permissions.collections(collection: "test", read_config: true)
        ]

        client.roles.create(role_name: role_name, permissions: required_permissions)

        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role.permissions.length).to eq(2)
        expect(role.collections_permissions).not_to be_nil
        expect(role.collections_permissions.length).to eq(1)
        expect(role.collections_permissions[0].actions).to eq(Set[RBAC::Actions::Collections::READ])
        expect(role.data_permissions.length).to eq(1)
        expect(role.data_permissions[0].actions).to eq(Set[RBAC::Actions::Data::CREATE, RBAC::Actions::Data::UPDATE])

        expect(client.roles.has_permissions(permissions: role.collections_permissions[0], role: role_name)).to be true
        expect(client.roles.has_permissions(permissions: role.data_permissions, role: role_name)).to be true
        expect(client.roles.has_permissions(permissions: required_permissions[1][0], role: role_name)).to be true
        expect(client.roles.has_permissions(permissions: required_permissions[0], role: role_name)).to be true
        expect(client.roles.has_permissions(permissions: required_permissions[1], role: role_name)).to be true
        expect(client.roles.has_permissions(permissions: required_permissions, role: role_name)).to be true
        expect(
          client.roles.has_permissions(
            permissions: required_permissions + [RBAC::Permissions.collections(collection: "test",
                                                                               delete_collection: true)],
            role: role_name
          )
        ).to be false
      ensure
        client.roles.delete(role_name)
      end
    end

    [RBAC::RoleScope::ALL, RBAC::RoleScope::MATCH].each do |scope|
      it "test_role_scope[RoleScope.#{scope.upcase}]" do
        client = rbac_client
        skip("This test requires Weaviate 1.28.4 or higher") if version_lower_than?(client, 1, 28, 4)
        role_name = "#{sanitize_name(node_name)}_scope"
        begin
          client.roles.delete(role_name)
          client.roles.create(role_name: role_name,
                              permissions: RBAC::Permissions.roles(role: "test", scope: scope, read: true))

          role = client.roles.get(role_name)
          expect(role).not_to be_nil
          expect(role.permissions.length).to eq(1)
          expect(role.roles_permissions[0].scope).to eq(scope)
        ensure
          client.roles.delete(role_name)
        end
      end
    end

    it "test_get_assigned_users" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      client.users.assign_roles(user_id: "admin-user", role_names: "viewer")
      assigned_users = client.roles.get_assigned_user_ids("viewer")
      expect(assigned_users.length).to eq(1)
      expect(assigned_users[0]).to eq("admin-user")
    end

    it "test_get_assigned_users_db" do
      client = rbac_client
      skip("This test requires Weaviate 1.30.0 or higher") if version_lower_than?(client, 1, 30, 0)

      names = sanitize_name(node_name)
      client.roles.delete(names)
      client.roles.create(role_name: names, permissions: RBAC::Permissions.roles(role: "test", read: true))

      client.users.db.create(user_id: names)

      client.users.db.assign_roles(user_id: names, role_names: names)
      assigned_users = client.roles.get_user_assignments(names)
      expect(assigned_users.length).to eq(1)
      expect(assigned_users[0].user_id).to eq(names)
      expect(assigned_users[0].user_type).to eq(Models::UserTypes::DB_DYNAMIC)

      client.roles.delete(names)
      client.users.db.delete(user_id: names)
    end

    it "test_get_assigned_oidc_db" do
      client = rbac_client
      skip("This test requires Weaviate 1.30.0 or higher") if version_lower_than?(client, 1, 30, 0)

      names = sanitize_name(node_name)
      client.roles.delete(names)
      client.roles.create(role_name: names, permissions: RBAC::Permissions.roles(role: "test", read: true))

      client.users.oidc.assign_roles(user_id: names, role_names: names)
      assigned_users = client.roles.get_user_assignments(names)
      expect(assigned_users.length).to eq(1)
      expect(assigned_users[0].user_id).to eq(names)
      expect(assigned_users[0].user_type).to eq(Models::UserTypes::OIDC)

      client.roles.delete(names)
    end

    it "test_permission_output_as_input" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      role_name = "PermissionOutputAsInput"
      begin
        client.roles.create(role_name: role_name, permissions: RBAC::Permissions.roles(role: "test", read: true))
        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role.permissions.length).to eq(1)

        client.roles.create(role_name: "#{role_name}2", permissions: role.permissions)

        role2 = client.roles.get(role_name)
        expect(role2).not_to be_nil
        expect(role2.permissions.length).to eq(1)
        expect(role2.permissions).to eq(role.permissions)
      ensure
        client.roles.delete(role_name)
        client.roles.delete(role_name: "#{role_name}2")
      end
    end

    it "test_permission_joining" do
      client = rbac_client
      skip("This test requires Weaviate 1.28.0 or higher") if version_lower_than?(client, 1, 28, 0)
      role_name = "PermissionJoining"
      begin
        client.roles.create(
          role_name: role_name,
          permissions: %w[test test* test_*].flat_map do |collection|
            [
              RBAC::Permissions.collections(collection: collection, read_config: true, update_config: true),
              RBAC::Permissions.collections(collection: collection, create_collection: true, update_config: true)
            ]
          end
        )
        role = client.roles.get(role_name)
        expect(role).not_to be_nil
        expect(role.permissions.length).to eq(3)
        expect(role.collections_permissions.length).to eq(3)
        all_actions = Set[RBAC::Actions::Collections::READ, RBAC::Actions::Collections::CREATE,
                          RBAC::Actions::Collections::UPDATE]
        expect(role.collections_permissions[0].actions).to eq(all_actions)
        expect(role.collections_permissions[1].actions).to eq(all_actions)
        expect(role.collections_permissions[2].actions).to eq(all_actions)
      ensure
        client.roles.delete(role_name)
      end
    end

    it "test_server_side_batching_with_auth" do
      collection_name = "TestSSBAuth"
      connect_to_docker_local(port: rbac_ports[0], grpc_port: rbac_ports[1],
                              auth_credentials: Batch5Helpers::RBAC_AUTH_CREDS) do |client|
        if version_lower_than?(client, 1, 36, 0)
          skip("Server-side batching not supported in Weaviate < 1.36.0")
        end
        collection = client.collections.create(collection_name)
        client.batch.stream do |batch|
          batch.add_object(collection_name)
          batch.add_object(collection_name)
          batch.add_object(collection_name)
        end
        begin
          expect(collection.length).to eq(3)
        ensure
          client.collections.delete(collection_name)
        end
      end
    end
  end
end
