# frozen_string_literal: true

require "tmpdir"

# Port of weaviate-python-client/integration/test_backup_v4.py.
#
# Python runs this module against the RBAC instance on (8093, 50065) with the "admin-key" API key.
# Only test_backup_and_restore_with_roles_and_users needs RBAC; in native mode (no auth, no RBAC)
# the module client connects to the default instance instead, so the filesystem-backend tests
# still run. The roles/users test goes through client_factory and is skipped natively.
module Batch5Specs
  RSpec.describe "backup_v4", :integration do
    include Batch5Helpers

    rbac_ports = [8093, 50_065]
    backend = Weaviate::Backup::BackupStorage::FILESYSTEM
    backup_status = Weaviate::Backup::BackupStatus

    paragraphs_ids = %w[
      fd34ccf4-1a2a-47ad-8446-231839366c3f
      2653442b-05d8-4fa3-b46a-d4a152eb63bc
      55374edb-17de-487f-86cb-9a9fbc30823f
      124ff6aa-597f-44d0-8c13-62fbb1e66888
      f787386e-7d1c-481f-b8c3-3dbfd8bbad85
    ]
    paragraphs_props = (1..5).map { |i| { "contents" => "paragraph #{i}" } }
    articles_ids = %w[
      2fd68cbc-21ff-4e19-aaef-62531dade974
      7ea3f7b8-65fd-4318-a842-ae9ba38ffdca
      769a4280-4b85-4e67-b685-07796c49a764
      97fcc234-fd16-4a40-82bb-d614e9bddf8b
      3fa435d3-6ab2-489d-abed-c25ec526c9f4
    ]
    articles_props = %w[a b c d e].map { |l| { "title" => "article #{l}", "datePublished" => Time.now.utc } }
    classes = %w[Paragraph Article]

    let(:rbac_ports) { rbac_ports }
    let(:backend) { backend }
    let(:classes) { classes }
    let(:articles_ids) { articles_ids }
    let(:paragraphs_ids) { paragraphs_ids }
    let(:client) { @module_client }

    # Python's module-scoped `client` fixture.
    before(:all) do
      @module_client =
        if IntegrationContext.native?
          Weaviate.connect_to_local(port: Batch5Helpers.default_port, grpc_port: Batch5Helpers.default_grpc_port)
        else
          Weaviate.connect_to_local(port: rbac_ports[0], grpc_port: rbac_ports[1],
                                    auth_credentials: Batch5Helpers::RBAC_AUTH_CREDS)
        end
      client = @module_client
      client.collections.delete(classes)

      col_para = client.collections.create(
        "Paragraph",
        properties: [Config::Property.new(name: "contents", data_type: Config::DataType::TEXT)],
        references: [Config::ReferenceProperty.new(name: "hasParagraphs", target_collection: "Paragraph")]
      )
      paragraphs_props.each_with_index do |para, i|
        col_para.data.insert(properties: para, uuid: paragraphs_ids[i])
      end

      col_articles = client.collections.create(
        "Article",
        properties: [
          Config::Property.new(name: "title", data_type: Config::DataType::TEXT),
          Config::Property.new(name: "datePublished", data_type: Config::DataType::DATE)
        ],
        references: [Config::ReferenceProperty.new(name: "hasParagraphs", target_collection: "Paragraph")]
      )

      articles_props.each_with_index do |art, i|
        col_articles.data.insert(properties: art, uuid: articles_ids[i])
        col_articles.data.reference_add(from_uuid: articles_ids[i], from_property: "hasParagraphs",
                                        to: paragraphs_ids[i])
      end
    end

    after(:all) do
      @module_client.collections.delete("Paragraph")
      @module_client.collections.delete("Article")
      @module_client.close
    end

    def wait_for_status(get_status, allowed)
      loop do
        status = get_status.call
        expect(allowed).to include(status.status)
        break if status.status == Weaviate::Backup::BackupStatus::SUCCESS

        sleep(0.1)
      end
    end

    it "test_create_and_restore_backup_with_waiting" do
      backup_id = unique_backup_id(node_name)

      # create backup
      classes = %w[Article Paragraph]
      resp = client.backup.create(backup_id: backup_id, backend: backend, wait_for_completion: true,
                                  include_collections: self.classes)
      expect(resp.status).to eq(backup_status::SUCCESS)
      classes.each { |cls| expect(resp.collections).to include(cls) }

      expect(client.collections.use("Article").length).to eq(articles_ids.length)
      expect(client.collections.use("Paragraph").length).to eq(paragraphs_ids.length)

      # check create status
      create_status = client.backup.get_create_status(backup_id, backend)
      expect(create_status.status).to eq(backup_status::SUCCESS)
      expect(create_status.backup_id.downcase).to eq(backup_id.downcase)

      # remove existing class
      client.collections.delete("Article")
      client.collections.delete("Paragraph")

      # restore backup
      restore = client.backup.restore(backup_id: backup_id, backend: backend, wait_for_completion: true,
                                      include_collections: self.classes)
      expect(restore.status).to eq(backup_status::SUCCESS)
      classes.each { |cls| expect(resp.collections).to include(cls) }

      # check data exists again
      expect(client.collections.use("Article").length).to eq(articles_ids.length)
      expect(client.collections.use("Paragraph").length).to eq(paragraphs_ids.length)

      # check restore status
      restore_status = client.backup.get_restore_status(backup_id, backend)
      expect(restore_status.status).to eq(backup_status::SUCCESS)
    end

    [["include0", ["Article"]], ["Article", "Article"]].each do |id, include|
      it "test_create_and_restore_backup_without_waiting[#{id}]" do
        backup_id = unique_backup_id(node_name)
        include_as_list = include.is_a?(Array) ? include.sort : [include]

        resp = client.backup.create(backup_id: backup_id, include_collections: include, backend: backend)
        expect(resp.status).to eq(backup_status::STARTED)
        expect(resp.collections.sort).to eq(include_as_list)

        # wait until created
        wait_for_status(
          -> { client.backup.get_create_status(backup_id, backend) },
          [backup_status::SUCCESS, backup_status::TRANSFERRED, backup_status::TRANSFERRING, backup_status::STARTED]
        )

        # check data still exists, then remove existing class
        expect(client.collections.use("Article").length).to eq(articles_ids.length)
        client.collections.delete("Article")

        # restore backup
        restore = client.backup.restore(backup_id: backup_id, include_collections: include, backend: backend)
        expect(restore.status).to eq(backup_status::STARTED)
        expect(restore.collections.sort).to eq(include_as_list)

        # wait until restored
        wait_for_status(
          -> { client.backup.get_restore_status(backup_id, backend) },
          [backup_status::SUCCESS, backup_status::TRANSFERRED, backup_status::TRANSFERRING, backup_status::STARTED,
           backup_status::FINALIZING]
        )

        # check data exists again
        expect(client.collections.use("Article").length).to eq(articles_ids.length)
      end
    end

    it "test_create_and_restore_1_of_2_classes" do
      backup_id = unique_backup_id(node_name)

      # check data exists
      expect(client.collections.use("Article").length).to eq(articles_ids.length)

      # create backup
      include = ["Article"]
      create = client.backup.create(backup_id: backup_id, include_collections: include, backend: backend,
                                    wait_for_completion: true)
      expect(create.status).to eq(backup_status::SUCCESS)

      status_create = client.backup.get_create_status(backup_id, backend)
      expect(status_create.status).to eq(backup_status::SUCCESS)

      # check data still exists and then remove existing class
      expect(client.collections.use("Article").length).to eq(articles_ids.length)
      client.collections.delete("Article")

      # restore backup
      restore = client.backup.restore(backup_id: backup_id, include_collections: include, backend: backend,
                                      wait_for_completion: true)
      expect(restore.status).to eq(backup_status::SUCCESS)

      # check data exists again
      expect(client.collections.use("Article").length).to eq(articles_ids.length)

      # check restore status
      restore_status = client.backup.get_restore_status(backup_id, backend)
      expect(restore_status.status).to eq(backup_status::SUCCESS)
    end

    it "test_fail_on_non_existing_class" do
      backup_id = unique_backup_id(node_name)
      class_name = "NonExistingClass"
      [client.backup.method(:create), client.backup.method(:restore)].each do |func|
        expect do
          func.call(backup_id: backup_id, backend: backend, include_collections: class_name)
        end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
      end
    end

    it "test_fail_restoring_backup_for_existing_class" do
      backup_id = unique_backup_id(node_name)
      class_name = ["Article"]
      create = client.backup.create(backup_id: backup_id, include_collections: class_name, backend: backend,
                                    wait_for_completion: true)
      expect(create.status).to eq(backup_status::SUCCESS)

      # fail restore
      expect do
        client.backup.restore(backup_id: backup_id, include_collections: class_name, backend: backend,
                              wait_for_completion: true)
      end.to raise_error(Weaviate::Exceptions::BackupFailedException)
    end

    it "test_fail_creating_existing_backup" do
      backup_id = unique_backup_id(node_name)
      class_name = ["Article"]
      create = client.backup.create(backup_id: backup_id, include_collections: class_name, backend: backend,
                                    wait_for_completion: true)
      expect(create.status).to eq(backup_status::SUCCESS)

      # fail create
      expect do
        client.backup.create(backup_id: backup_id, include_collections: class_name, backend: backend,
                             wait_for_completion: true)
      end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
    end

    it "test_fail_restoring_non_existing_backup" do
      backup_id = unique_backup_id(node_name)
      expect do
        client.backup.restore(backup_id: backup_id, backend: backend, wait_for_completion: true)
      end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
    end

    it "test_fail_checking_status_for_non_existing_restore" do
      backup_id = unique_backup_id(node_name)
      [client.backup.method(:get_restore_status), client.backup.method(:get_create_status)].each do |func|
        expect do
          func.call(backup_id: backup_id, backend: backend)
        end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
      end
    end

    it "test_fail_creating_backup_for_both_include_and_exclude_classes" do
      backup_id = unique_backup_id(node_name)

      [client.backup.method(:create), client.backup.method(:restore)].each do |func|
        expect do
          func.call(backup_id: backup_id, include_collections: "Article", exclude_collections: "Paragraph",
                    backend: backend, wait_for_completion: true)
        end.to raise_error(TypeError)
      end
    end

    [false, true].each do |dynamic_backup_location|
      it "test_backup_and_restore_with_dynamic_location[#{dynamic_backup_location}]" do
        backup_id = unique_backup_id(node_name)

        conf_create = nil
        conf_restore = nil
        backup_location = nil
        if dynamic_backup_location
          skip("Cancel backups is only supported from 1.27.2") if client.connection.weaviate_version.is_lower_than(1, 27, 2)

          backup_location = Weaviate::Classes::Backup::BackupLocation::FileSystem.new(path: Dir.mktmpdir)
        end

        article = client.collections.use("Article")

        # create backup
        create = article.backup.create(backup_id: backup_id, backend: backend, wait_for_completion: true,
                                       config: conf_create, backup_location: backup_location)
        expect(create.status).to eq(backup_status::SUCCESS)

        expect(article.length).to eq(articles_ids.length)

        # check create status
        create_status = article.backup.get_create_status(backup_id: backup_id, backend: backend,
                                                         backup_location: backup_location)
        expect(create_status.status).to eq(backup_status::SUCCESS)

        # remove existing class
        client.collections.delete("Article")

        # restore backup
        restore = article.backup.restore(backup_id: backup_id, backend: backend, wait_for_completion: true,
                                         config: conf_restore, backup_location: backup_location)
        expect(restore.status).to eq(backup_status::SUCCESS)

        # check data exists again
        expect(article.length).to eq(articles_ids.length)

        # check restore status
        restore_status = article.backup.get_restore_status(backup_id, backend, backup_location: backup_location)
        expect(restore_status.status).to eq(backup_status::SUCCESS)
      end
    end

    it "test_backup_and_restore_with_collection_and_config_1_24_x" do
      if client.connection.weaviate_version.is_lower_than(1, 25, 0)
        skip("Backup config is only supported from Weaviate 1.25.0")
      end

      backup_id = unique_backup_id(node_name)

      article = client.collections.use("Article")

      # create backup
      create = article.backup.create(
        backup_id: backup_id, backend: backend, wait_for_completion: true,
        config: Weaviate::Classes::Backup::BackupConfigCreate.new(
          cpu_percentage: 60, compression_level: Weaviate::Classes::Backup::BackupCompressionLevel::BEST_SPEED
        )
      )
      expect(create.status).to eq(backup_status::SUCCESS)

      expect(article.length).to eq(articles_ids.length)

      # check create status
      create_status = article.backup.get_create_status(backup_id, backend)
      expect(create_status.status).to eq(backup_status::SUCCESS)

      # remove existing class
      client.collections.delete("Article")

      # restore backup
      restore = article.backup.restore(
        backup_id: backup_id, backend: backend, wait_for_completion: true,
        config: Weaviate::Classes::Backup::BackupConfigRestore.new(cpu_percentage: 70)
      )
      expect(restore.status).to eq(backup_status::SUCCESS)

      # check data exists again
      expect(article.length).to eq(articles_ids.length)

      # check restore status
      restore_status = article.backup.get_restore_status(backup_id, backend)
      expect(restore_status.status).to eq(backup_status::SUCCESS)
    end

    [false, true].each do |dynamic_backup_location|
      it "test_cancel_backup_create[#{dynamic_backup_location}]" do
        # Cancel backup create without waiting.
        backup_id = unique_backup_id(node_name)
        if client.connection.weaviate_version.is_lower_than(1, 24, 25)
          skip("Cancel backups is only supported from 1.24.25")
        end

        backup_location = nil
        if dynamic_backup_location
          skip("Cancel backups is only supported from 1.27.2") if client.connection.weaviate_version.is_lower_than(1, 27, 2)

          backup_location = Weaviate::Classes::Backup::BackupLocation::FileSystem.new(path: Dir.mktmpdir)
        end

        resp = client.backup.create(backup_id: backup_id, backend: backend, backup_location: backup_location,
                                    include_collections: classes)
        expect(resp.status).to eq(backup_status::STARTED)

        expect(client.backup.cancel(backup_id: backup_id, backend: backend, backup_location: backup_location)).to be true

        # async process
        start = Time.now
        while Time.now - start < 5
          status_resp = client.backup.get_create_status(backup_id: backup_id, backend: backend,
                                                        backup_location: backup_location)
          break if status_resp.status == backup_status::CANCELED

          sleep(0.1)
        end
        status_resp = client.backup.get_create_status(backup_id: backup_id, backend: backend,
                                                      backup_location: backup_location)
        # there can be a race between the cancel and the backup completion
        expect([backup_status::CANCELED, backup_status::SUCCESS]).to include(status_resp.status)
      end
    end

    [false, true].each do |dynamic_backup_location|
      it "test_cancel_backup_restore[#{dynamic_backup_location}]" do
        # Cancel backup restore without waiting.
        backup_id = unique_backup_id(node_name)
        if client.connection.weaviate_version.is_lower_than(1, 36, 0)
          skip("Cancel restores is only supported from 1.36.0")
        end

        backup_location = nil
        if dynamic_backup_location
          backup_location = Weaviate::Classes::Backup::BackupLocation::FileSystem.new(path: Dir.mktmpdir)
        end

        c_name = "Restore"
        # Not in Python: a previous parametrization may have left a restored "Restore" collection behind.
        client.collections.delete(c_name)
        c = client.collections.create(c_name,
                                      properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)])
        c.data.insert({ "name" => "test" })

        resp = client.backup.create(backup_id: backup_id, backend: backend, backup_location: backup_location,
                                    include_collections: [c_name], wait_for_completion: true)
        expect(resp.status).to eq(backup_status::SUCCESS)

        client.collections.delete(c_name)

        resp = client.backup.restore(backup_id: backup_id, backend: backend, backup_location: backup_location,
                                     include_collections: [c_name])
        expect(resp.status).to eq(backup_status::STARTED)

        expect(
          client.backup.cancel(backup_id: backup_id, backend: backend, backup_location: backup_location,
                               operation: "restore")
        ).to be true

        start = Time.now
        while Time.now - start < 5
          status_resp = client.backup.get_restore_status(backup_id: backup_id, backend: backend,
                                                         backup_location: backup_location)
          break if status_resp.status == backup_status::CANCELED

          sleep(0.1)
        end

        status_resp = client.backup.get_restore_status(backup_id: backup_id, backend: backend,
                                                       backup_location: backup_location)
        # there can be a race between the cancel and the backup completion
        expect([backup_status::CANCELED, backup_status::SUCCESS]).to include(status_resp.status)
      ensure
        client.collections.delete("Restore")
      end
    end

    it "test_backup_and_restore_with_roles_and_users" do
      backup_id = unique_backup_id(node_name)
      client = client_factory(ports: rbac_ports, auth_credentials: Batch5Helpers::RBAC_AUTH_CREDS)
      skip("User and roles are only supported from Weaviate 1.30.10") if client.connection.weaviate_version.is_lower_than(1, 30, 10)

      name = sanitize_name("backup_v4_spec.rb_#{node_name}")
      client.collections.delete(name)
      client.collections.create(name)

      client.users.db.delete(user_id: name)
      client.users.db.create(user_id: name)

      client.roles.delete(role_name: name)
      client.roles.create(role_name: name,
                          permissions: RBAC::Permissions.collections(collection: "*", create_collection: true))

      resp = client.backup.create(backup_id: backup_id, backend: backend, wait_for_completion: true,
                                  include_collections: [name])
      expect(resp.status).to eq(backup_status::SUCCESS)

      client.users.db.delete(user_id: name)
      client.roles.delete(role_name: name)
      client.collections.delete(name)
      expect(client.users.db.get(user_id: name)).to be_nil
      expect(client.roles.get(role_name: name)).to be_nil

      client.backup.restore(backup_id: backup_id, backend: backend, wait_for_completion: true,
                            roles_restore: "all", users_restore: "all")

      expect(client.users.db.get(user_id: name)).not_to be_nil
      expect(client.roles.get(role_name: name)).not_to be_nil
    end

    it "test_list_backup" do
      # List all backups.
      backup_id = unique_backup_id(node_name)
      skip("List backups is only supported from 1.30.0") if client.connection.weaviate_version.is_lower_than(1, 30, 0)

      resp = client.backup.create(backup_id: backup_id, backend: backend)
      expect(resp.status).to eq(backup_status::STARTED)

      backups = client.backup.list_backups(backend: backend)
      expect(backups.map { |b| b.backup_id.downcase }).to include(backup_id.downcase)

      # wait until created
      wait_for_status(
        -> { client.backup.get_create_status(backup_id, backend) },
        [backup_status::SUCCESS, backup_status::TRANSFERRED, backup_status::TRANSFERRING, backup_status::STARTED]
      )
    end

    it "test_list_backup_ascending_order" do
      # List all backups in ascending order.
      backup_id = unique_backup_id(node_name)
      if client.connection.weaviate_version.is_lower_than(1, 33, 2)
        skip("List backups sorting is only supported from 1.33.2")
      end

      resp = client.backup.create(backup_id: backup_id, backend: backend)
      expect(resp.status).to eq(backup_status::STARTED)

      wait_for_status(
        -> { client.backup.get_create_status(backup_id, backend) },
        [backup_status::SUCCESS, backup_status::TRANSFERRED, backup_status::TRANSFERRING, backup_status::STARTED]
      )

      backups = client.backup.list_backups(backend: backend, sort_by_starting_time_asc: true)
      expect(backups.map { |b| b.backup_id.downcase }).to include(backup_id.downcase)

      # Python: sorted(backups, key=lambda b: b.started_at or b.backup_id) == backups
      expect(backups.sort_by.with_index { |b, i| [b.started_at || b.backup_id, i] }).to eq(backups)
    end

    describe "with artist_alias" do
      # Python's `artist_alias` fixture.
      let(:artist_alias) do
        skip("overwriteAlias is only supported from 1.33.0 onwards") if client.connection.weaviate_version.is_lower_than(1, 32, 0)

        client.alias.create(target_collection: "Article", alias_name: "Literature")
        @alias_created = true
        "Literature"
      end

      after { client.alias.delete(alias_name: "Literature") if @alias_created }

      it "test_overwrite_alias_true" do
        # Restore backups with overwrite=true.
        artist_alias = self.artist_alias
        backup_id = unique_backup_id(node_name)
        client.backup.create(backup_id: backup_id, backend: backend, include_collections: ["Article"],
                             wait_for_completion: true)

        client.collections.delete("Article")
        client.alias.update(alias_name: artist_alias, new_target_collection: "Paragraph")

        client.backup.restore(backup_id: backup_id, backend: backend, include_collections: ["Article"],
                              wait_for_completion: true, overwrite_alias: true)

        literature = client.alias.get(alias_name: "Literature")
        expect(literature).not_to be_nil, "expect alias exists"
        expect(literature.collection).to eq("Article"), "alias must point to the original collection"
      end
    end

    it "test_incremental_backup" do
      # Create and restore incremental backup.
      skip("List backups is only supported from 1.37.0") if client.connection.weaviate_version.is_lower_than(1, 37, 0)

      backup_id = unique_backup_id(node_name)
      base_backup_id = "#{backup_id}_base"

      # create base backup
      client.backup.create(backup_id: base_backup_id, backend: backend, include_collections: ["Article"],
                           wait_for_completion: true)

      # create incremental backup
      client.backup.create(backup_id: backup_id, backend: backend, include_collections: ["Article"],
                           wait_for_completion: true, incremental_base_backup_id: base_backup_id)

      # remove existing class
      client.collections.delete("Article")

      # restore incremental backup
      client.backup.restore(backup_id: backup_id, backend: backend, include_collections: ["Article"],
                            wait_for_completion: true)

      # check data exists again
      expect(client.collections.use("Article").length).to eq(articles_ids.length)
    end
  end
end
