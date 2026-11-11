# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_users.py.
#
# Every test needs the RBAC docker-compose instance on (8092, 50063); they are skipped in native mode.
module Batch5Specs
  RSpec.describe "users", :integration do
    include Batch5Helpers

    rbac_ports = [8092, 50_063]
    let(:rbac_ports) { rbac_ports }

    def unique_user_id(name) = sanitize_name(name).downcase

    def rbac_client(api_key = "admin-key")
      client_factory(ports: rbac_ports, auth_credentials: Weaviate::Auth.api_key(api_key))
    end

    def skip_if_lower_than!(client, major, minor, patch)
      return unless client.connection.weaviate_version.is_lower_than(major, minor, patch)

      skip("This test requires Weaviate #{major}.#{minor}.#{patch} or higher")
    end

    def connect_rbac(api_key, &block)
      port, grpc_port = IntegrationContext.resolve_ports(rbac_ports)
      Weaviate.connect_to_local(port: port, grpc_port: grpc_port,
                                auth_credentials: Weaviate::Auth.api_key(api_key), &block)
    end

    it "test_own_user" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 28, 0)
      user = client.users.get_my_user
      expect(user.roles.length).to be > 0
      expect(user.user_id).to eq("admin-user")
    end

    it "test_get_user_roles_deprecated" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 28, 0)
      roles = client.users.get_assigned_roles("admin-user")
      expect(roles.length).to be > 0
    end

    it "test_get_user_roles_db" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)
      roles_base = client.users.db.get_assigned_roles(user_id: "admin-user")
      names = roles_base.keys
      expect(roles_base.length).to be > 0
      expect(roles_base[names[0]]).to be_a(Models::RoleBase)

      roles = client.users.db.get_assigned_roles(user_id: "admin-user", include_permissions: true)
      expect(roles.length).to be > 0
      expect(roles[names[0]]).to be_a(Models::Role)
    end

    it "test_get_user_roles_oidc" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)
      roles_base = client.users.oidc.get_assigned_roles(user_id: "admin-user")
      names = roles_base.keys
      expect(roles_base.length).to be > 0
      expect(roles_base[names[0]]).to be_a(Models::RoleBase)

      roles = client.users.oidc.get_assigned_roles(user_id: "admin-user", include_permissions: true)
      expect(roles.length).to be > 0
      expect(roles[names[0]]).to be_a(Models::Role)
    end

    it "test_get_user_with_no_roles" do
      client = rbac_client("custom-key")
      skip_if_lower_than!(client, 1, 28, 0)
      user = client.users.get_my_user
      expect(user.roles.length).to eq(0)
    end

    it "test_get_static_db_user" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)
      user = client.users.db.get(user_id: "admin-user")
      expect(user.role_names.length).to be > 0
      expect(user.user_id).to eq("admin-user")
      expect(user.active).to be true
      expect(user.user_type).to eq(Models::UserTypes::DB_STATIC)
    end

    it "test_create_user_and_get" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      api_key = client.users.db.create(user_id: user_id)
      connect_rbac(api_key) do |client2|
        user = client2.users.get_my_user
        expect(user.user_id).to eq(user_id)
      end
      dynamic_user = client.users.db.get(user_id: user_id)
      expect(dynamic_user).not_to be_nil
      expect(dynamic_user.user_id).to eq(user_id)
      expect(dynamic_user.user_type).to eq(Models::UserTypes::DB_DYNAMIC)
      expect(client.users.db.delete(user_id: user_id)).to be true
    end

    it "test_delete_user" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      client.users.db.create(user_id: user_id)
      expect(client.users.db.delete(user_id: user_id)).to be true

      expect(client.users.db.delete(user_id: "I-do-not-exist")).to be false
    end

    it "test_rotate_user_key" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      api_key = client.users.db.create(user_id: user_id)
      connect_rbac(api_key) do |client2|
        expect(client2.users.get_my_user.user_id).to eq(user_id)
      end

      api_key_new = client.users.db.rotate_key(user_id: user_id)
      connect_rbac(api_key_new) do |client2|
        expect(client2.users.get_my_user.user_id).to eq(user_id)
      end

      expect(client.users.db.delete(user_id: user_id)).to be true
    end

    it "test_de_activate" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      client.users.db.create(user_id: user_id)

      expect(client.users.db.deactivate(user_id: user_id)).to be true
      # second deactivation returns a conflict => false
      expect(client.users.db.deactivate(user_id: user_id)).to be false
      user = client.users.db.get(user_id: user_id)
      expect(user.active).to be false
      expect(client.users.db.activate(user_id: user_id)).to be true
      # second activation returns a conflict => false
      expect(client.users.db.activate(user_id: user_id)).to be false
      user = client.users.db.get(user_id: user_id)
      expect(user.active).to be true

      client.users.db.delete(user_id: user_id)
    end

    it "test_deactivate_and_revoke" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      api_key_old = client.users.db.create(user_id: user_id)
      expect(client.users.db.deactivate(user_id: user_id, revoke_key: true)).to be true

      expect { connect_rbac(api_key_old) }.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

      # re-activating is not enough
      expect(client.users.db.activate(user_id: user_id)).to be true
      expect { connect_rbac(api_key_old) }.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeError)

      api_key_new = client.users.db.rotate_key(user_id: user_id)

      connect_rbac(api_key_new) do |client2|
        expect(client2.users.get_my_user.user_id).to eq(user_id)
      end

      client.users.db.delete(user_id: user_id)
    end

    it "test_deprecated_syntax" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)
      user_id = unique_user_id(node_name)
      client.users.db.create(user_id: user_id)
      roles = client.users.db.get_assigned_roles(user_id: user_id)
      expect(roles.length).to eq(0)
      client.users.db.delete(user_id: user_id)
    end

    it "test_list_all_users" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      5.times do |i|
        client.users.db.delete(user_id: "list-all-user-#{i}")
        client.users.db.create(user_id: "list-all-user-#{i}")
      end

      users = client.users.db.list_all
      dynamic_users = users.select { |user| user.user_id.start_with?("list-all-") }
      expect(dynamic_users.length).to eq(5)
      5.times { |i| client.users.db.delete(user_id: "list-all-#{i}") }
    end

    it "test_get_user_created_at_and_api_key_first_letters" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      client.users.db.create(user_id: user_id)
      begin
        user = client.users.db.get(user_id: user_id)
        expect(user).not_to be_nil
        expect(user.created_at).not_to be_nil
        expect(user.api_key_first_letters).not_to be_nil
        expect(user.api_key_first_letters.length).to be > 0
      ensure
        client.users.db.delete(user_id: user_id)
      end
    end

    it "test_get_user_include_last_used_time" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      api_key = client.users.db.create(user_id: user_id)
      begin
        # log in with the new user to generate a lastUsedAt timestamp
        connect_rbac(api_key) do |client2|
          expect(client2.users.get_my_user.user_id).to eq(user_id)
        end

        # without include_last_used_time, last_used_time should be nil
        user = client.users.db.get(user_id: user_id)
        expect(user).not_to be_nil
        expect(user.last_used_time).to be_nil

        # with include_last_used_time: true, last_used_time should be populated
        user = client.users.db.get(user_id: user_id, include_last_used_time: true)
        expect(user).not_to be_nil
        expect(user.last_used_time).not_to be_nil
      ensure
        client.users.db.delete(user_id: user_id)
      end
    end

    it "test_list_all_include_last_used_time" do
      client = rbac_client
      skip_if_lower_than!(client, 1, 30, 0)

      user_id = unique_user_id(node_name)
      api_key = client.users.db.create(user_id: user_id)
      begin
        # log in with the new user to generate a lastUsedAt timestamp
        connect_rbac(api_key) do |client2|
          expect(client2.users.get_my_user.user_id).to eq(user_id)
        end

        # without include_last_used_time, last_used_time should be nil
        users = client.users.db.list_all
        target = users.find { |u| u.user_id == user_id }
        expect(target).not_to be_nil
        expect(target.created_at).not_to be_nil
        expect(target.api_key_first_letters).not_to be_nil
        expect(target.last_used_time).to be_nil

        # with include_last_used_time: true, last_used_time should be populated
        users = client.users.db.list_all(include_last_used_time: true)
        target = users.find { |u| u.user_id == user_id }
        expect(target).not_to be_nil
        expect(target.last_used_time).not_to be_nil
      ensure
        client.users.db.delete(user_id: user_id)
      end
    end
  end
end
