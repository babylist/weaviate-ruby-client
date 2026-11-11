# frozen_string_literal: true

# Port of the backup/cluster tests in mock_tests/test_collection.py, plus mock coverage
# of the other REST-only namespaces (alias, users, groups, export, tokenization, debug).
RSpec.describe "REST feature namespaces (mock)" do
  include_context "mock weaviate"

  # Re-register the startup endpoints with a different server version.
  def mock_version!(version)
    httpserver.clear
    httpserver.expect_request("/v1/.well-known/ready").respond_with_json({})
    httpserver.expect_request("/v1/meta").respond_with_json({ "version" => version })
  end

  after { @client&.close }

  def client
    @client ||= connect_mock_client
  end

  %w[minimal verbose].each do |output|
    it "test_node_with_timeout[#{output}]" do
      mock_version!("1.34")
      httpserver.expect_request("/v1/nodes").respond_with_json(
        { "nodes" => [{ "status" => "TIMEOUT", "shards" => nil, "name" => "node1" }] }
      )

      nodes = client.cluster.nodes(output: output)
      expect(nodes[0].status).to eq("TIMEOUT")
    end
  end

  it "test_cluster_statistics" do
    mock_version!("1.34")
    httpserver.expect_request("/v1/cluster/statistics").respond_with_json(
      {
        "statistics" => [
          {
            "candidates" => {}, "dbLoaded" => true, "initialLastAppliedIndex" => 119, "isVoter" => true,
            "leaderAddress" => "172.16.11.11:8300", "leaderId" => "weaviate-0", "name" => "weaviate-0", "open" => true,
            "raft" => {
              "appliedIndex" => "144", "commitIndex" => "144", "fsmPending" => "0", "lastContact" => "0",
              "lastLogIndex" => "144", "lastLogTerm" => "31",
              "latestConfiguration" => [{ "address" => "172.16.11.11:8300", "id" => "weaviate-0", "suffrage" => 0 }],
              "latestConfigurationIndex" => "0", "numPeers" => "2", "state" => "Leader", "term" => "31"
            },
            "ready" => true, "status" => "HEALTHY"
          }
        ],
        "synchronized" => true
      }
    )

    stats = client.cluster.statistics
    expect(stats.synchronized).to be(true)
    expect(stats.statistics.length).to eq(1)
    expect(stats.statistics[0].name).to eq("weaviate-0")
    expect(stats.statistics[0].status).to eq("HEALTHY")
    expect(stats.statistics[0].raft.state).to eq("Leader")
    expect(stats.statistics[0].raft.latest_configuration[0].node_id).to eq("weaviate-0")
  end

  it "test_backup_cancel_while_create_and_restore" do
    no_auth_mock!
    backup_id = "id"
    body = ->(status) { { "collections" => ["backupTest"], "status" => status, "path" => "path", "id" => backup_id } }
    httpserver.expect_request("/v1/backups/filesystem").respond_with_json(body.call("STARTED"))
    httpserver.expect_request("/v1/backups/filesystem/#{backup_id}").respond_with_json(body.call("CANCELED"))
    httpserver.expect_request("/v1/backups/filesystem/#{backup_id}/restore").respond_with_json(body.call("CANCELED"))

    expect do
      client.backup.create(backup_id: backup_id, backend: Weaviate::Classes::Backup::BackupStorage::FILESYSTEM,
                           wait_for_completion: true)
    end.to raise_error(Weaviate::Exceptions::BackupCanceledError)

    expect do
      client.backup.restore(backup_id: backup_id, backend: Weaviate::Classes::Backup::BackupStorage::FILESYSTEM,
                            wait_for_completion: true)
    end.to raise_error(Weaviate::Exceptions::BackupCanceledError)
  end

  it "test_backup_create_include_roles_users" do
    no_auth_mock!
    bodies = []
    httpserver.expect_request("/v1/backups/filesystem", method: "POST").respond_with_handler do |req|
      bodies << req.json
      [200, { "content-type" => "application/json" }, JSON.generate({ "status" => "STARTED", "path" => "path", "id" => "id" })]
    end

    client.backup.create(backup_id: "id", backend: Weaviate::Classes::Backup::BackupStorage::FILESYSTEM)
    expect(bodies[0]).not_to include("includeRoles", "includeUsers")

    # the mock reports 1.36, below the 1.40 minimum
    expect do
      client.backup.create(backup_id: "id", backend: Weaviate::Classes::Backup::BackupStorage::FILESYSTEM,
                           include_roles: "r")
    end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
  end

  it "test_backup_create_include_roles_users_sent" do
    mock_version!("1.40.0")
    bodies = []
    httpserver.expect_request("/v1/backups/filesystem", method: "POST").respond_with_handler do |req|
      bodies << req.json
      [200, { "content-type" => "application/json" }, JSON.generate({ "status" => "STARTED", "path" => "path", "id" => "id" })]
    end

    client.backup.create(backup_id: "id", backend: Weaviate::Classes::Backup::BackupStorage::FILESYSTEM,
                         include_roles: "r", include_users: %w[u1 u2])
    expect(bodies[0]["includeRoles"]).to eq(["r"])
    expect(bodies[0]["includeUsers"]).to eq(%w[u1 u2])
  end

  it "collection backup and backup status helpers" do
    no_auth_mock!
    httpserver.expect_request("/v1/backups/s3", method: "POST", json: {
                                "id" => "b1", "include" => ["Test"], "exclude" => [], "incremental_base_backup_id" => nil,
                                "config" => { "CPUPercentage" => 40, "path" => "/p", "bucket" => "bk" }
                              }).respond_with_json({ "id" => "b1", "status" => "STARTED", "path" => "/p", "classes" => ["Test"] })
    httpserver.expect_request("/v1/backups/s3/b1", method: "GET", query: { "path" => "/p", "bucket" => "bk" })
              .respond_with_json({ "status" => "SUCCESS", "path" => "/p" })
    httpserver.expect_request("/v1/backups/s3", method: "GET", query: { "order" => "asc" })
              .respond_with_json([{ "id" => "b1", "status" => "SUCCESS", "classes" => ["Test"] }])
    httpserver.expect_request("/v1/backups/s3/b1/restore", method: "DELETE").respond_with_data("", status: 204)

    backup = Weaviate::Collections::Backups::CollectionBackup.new(connection: client.connection, name: "Test")
    loc = Weaviate::Classes::Backup::BackupLocation::S3.new(path: "/p", bucket: "bk")
    res = backup.create(backup_id: "B1", backend: "s3", wait_for_completion: true, backup_location: loc,
                        config: Weaviate::Classes::Backup::BackupConfigCreate.new(cpu_percentage: 40))
    expect(res).to eq(Weaviate::Outputs::Backup::BackupStatusReturn.new(status: "SUCCESS", path: "/p", backup_id: "B1"))
    expect(client.backup.list_backups(backend: "s3", sort_by_starting_time_asc: true).first.collections).to eq(["Test"])
    expect(client.backup.cancel(backup_id: "b1", backend: "s3", operation: "restore")).to be(true)
  end

  it "aliases" do
    no_auth_mock!
    httpserver.expect_request("/v1/aliases", method: "GET", query: { "class" => "Books" })
              .respond_with_json({ "aliases" => [{ "alias" => "B", "class" => "Books" }] })
    httpserver.expect_request("/v1/aliases", method: "POST", json: { "class" => "Books", "alias" => "B" })
              .respond_with_json({})
    httpserver.expect_request("/v1/aliases/B", method: "GET").respond_with_json({ "alias" => "B", "class" => "Books" })
    httpserver.expect_request("/v1/aliases/B", method: "PUT", json: { "class" => "Other" }).respond_with_json({})
    httpserver.expect_request("/v1/aliases/B", method: "DELETE").respond_with_data("", status: 204)
    httpserver.expect_request("/v1/aliases/X", method: "GET").respond_with_json({}, status: 404)

    expect(client.alias.list_all(collection: "Books"))
      .to eq({ "B" => Weaviate::Aliases::AliasReturn.new(alias: "B", collection: "Books") })
    expect(client.alias.create(alias_name: "B", target_collection: "Books")).to be_nil
    expect(client.alias.get(alias_name: "B").collection).to eq("Books")
    expect(client.alias.get(alias_name: "X")).to be_nil
    expect(client.alias.exists(alias_name: "X")).to be(false)
    expect(client.alias.update(alias_name: "B", new_target_collection: "Other")).to be(true)
    expect(client.alias.delete(alias_name: "B")).to be(true)
  end

  it "users and groups" do
    no_auth_mock!
    httpserver.expect_request("/v1/users/own-info").respond_with_json(
      { "username" => "me", "roles" => [{ "name" => "admin", "permissions" => [] }], "groups" => ["g"] }
    )
    httpserver.expect_request("/v1/users/db/u1", method: "GET", query: { "includeLastUsedTime" => "true" })
              .respond_with_json({ "userId" => "u1", "roles" => ["r"], "active" => true, "dbUserType" => "db_user",
                                   "createdAt" => "2025-01-02T03:04:05Z", "lastUsedAt" => "0001-01-01T00:00:00Z" })
    httpserver.expect_request("/v1/users/db/u2", method: "POST").respond_with_json({ "apikey" => "key" }, status: 201)
    httpserver.expect_request("/v1/authz/users/u 1/roles/oidc", query: { "includeFullRoles" => "false" })
              .respond_with_json([{ "name" => "viewer", "permissions" => [] }])
    httpserver.expect_request("/v1/authz/users/u1/assign", method: "POST",
                                                           json: { "roles" => ["r"], "userType" => "db" })
              .respond_with_json({})
    httpserver.expect_request("/v1/authz/groups/oidc").respond_with_json(%w[g1 g2])

    me = client.users.get_my_user
    expect(me.user_id).to eq("me")
    expect(me.roles.keys).to eq(["admin"])
    user = client.users.db.get(user_id: "u1", include_last_used_time: true)
    expect(user.user_type).to eq(Weaviate::Outputs::Users::UserTypes::DB_DYNAMIC)
    expect(user.created_at).to eq(Time.utc(2025, 1, 2, 3, 4, 5))
    expect(user.last_used_time).to be_nil
    expect(client.users.db.create(user_id: "u2")).to eq("key")
    expect(client.users.oidc.get_assigned_roles(user_id: "u 1"))
      .to eq({ "viewer" => Weaviate::RBAC::Models::RoleBase.new(name: "viewer") })
    expect(client.users.db.assign_roles(user_id: "u1", role_names: "r")).to be_nil
    expect(client.groups.oidc.get_known_group_names).to eq(%w[g1 g2])
  end

  it "export, tokenization and replication are version gated" do
    no_auth_mock!
    expect { client.export.get_status(export_id: "e", backend: "s3") }
      .to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
    expect { client.tokenization.text("hi", "word") }
      .to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
  end

  it "export and tokenization on 1.37" do
    mock_version!("1.37.0")
    httpserver.expect_request("/v1/export/s3", method: "POST",
                                               json: { "id" => "e1", "file_format" => "parquet", "include" => ["Books"] })
              .respond_with_json({ "id" => "e1", "backend" => "s3", "path" => "/p", "status" => "STARTED" })
    httpserver.expect_request("/v1/export/s3/e1", method: "GET").respond_with_json(
      { "id" => "e1", "backend" => "s3", "path" => "/p", "status" => "SUCCESS", "tookInMs" => 5,
        "shardStatus" => { "Books" => { "s1" => { "status" => "SUCCESS", "objectsExported" => 3 } } } }
    )
    httpserver.expect_request("/v1/tokenize", method: "POST",
                                              json: { "text" => "Hello", "tokenization" => "word",
                                                      "stopwordPresets" => { "custom" => ["foo"] } })
              .respond_with_json({ "indexed" => ["hello"], "query" => ["hello"] })

    status = client.export.create(export_id: "E1", backend: "s3", file_format: "parquet",
                                  include_collections: "books", wait_for_completion: true)
    expect(status.took_in_ms).to eq(5)
    expect(status.shard_status["Books"]["s1"].objects_exported).to eq(3)
    result = client.tokenization.text("Hello", "word", stopword_presets: { "custom" => ["foo"] })
    expect(result).to eq(Weaviate::Outputs::Tokenization::TokenizeResult.new(indexed: ["hello"], query: ["hello"]))
    expect { client.tokenization.text("x", "word", stopwords: Object.new, stopword_presets: {}) }
      .to raise_error(ArgumentError, /mutually exclusive/)
  end

  it "replication and debug" do
    no_auth_mock!
    op_id = "11111111-2222-3333-4444-555555555555"
    httpserver.expect_request("/v1/replication/replicate", method: "POST", json: {
                                "collection" => "C", "shard" => "s", "sourceNode" => "a", "targetNode" => "b", "type" => "COPY"
                              }).respond_with_json({ "id" => op_id })
    httpserver.expect_request("/v1/replication/replicate/#{op_id}", method: "GET", query: { "includeHistory" => "true" })
              .respond_with_json({ "id" => op_id, "collection" => "C", "shard" => "s", "sourceNode" => "a",
                                   "targetNode" => "b", "type" => "MOVE",
                                   "status" => { "state" => "READY", "errors" => nil },
                                   "statusHistory" => [{ "state" => "REGISTERED", "errors" => [] }] })
    httpserver.expect_request("/v1/replication/sharding-state", query: { "collection" => "C" })
              .respond_with_json({ "shardingState" => { "collection" => "C",
                                                        "shards" => [{ "shard" => "s", "replicas" => %w[a b] }] } })
    httpserver.expect_request("/v1/objects/C/#{op_id}", query: { "tenant" => "t" }).respond_with_json(
      { "class" => "C", "creationTimeUnix" => 1_700_000_000_000, "lastUpdateTimeUnix" => 1_700_000_000_000,
        "properties" => { "a" => 1 }, "id" => op_id, "tenant" => "t" }
    )

    expect(client.cluster.replicate(collection: "C", shard: "s", source_node: "a", target_node: "b")).to eq(op_id)
    op = client.cluster.replications.get(uuid: op_id, include_history: true)
    expect(op.transfer_type).to eq(Weaviate::Classes::Replication::ReplicationType::MOVE)
    expect(op.status_history.first.state).to eq("REGISTERED")
    state = client.cluster.query_sharding_state(collection: "C")
    expect(state.shards.first).to eq(Weaviate::Outputs::Cluster::ShardReplicas.new(name: "s", replicas: %w[a b]))
    obj = client.debug.get_object_over_rest("C", op_id, tenant: "t")
    expect(obj.creation_time).to eq(Time.at(1_700_000_000).utc)
    expect(obj.properties).to eq({ "a" => 1 })
  end
end
