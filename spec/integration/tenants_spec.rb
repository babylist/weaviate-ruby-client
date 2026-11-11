# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_tenants.py.
module Batch5Specs
  RSpec.describe "tenants", :integration do
    include Batch5Helpers

    def mt_collection(**kwargs)
      collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                         multi_tenancy_config: Config::Configure.multi_tenancy(enabled: true), **kwargs)
    end

    it "test_shards_on_tenants" do
      collection = mt_collection
      collection.tenants.create(Tenant.new(name: "tenant1"))
      client = client_factory

      nodes = client.cluster.nodes(collection.name, output: "verbose")
      count = nodes.sum { |node| node.shards.length }

      expect(count).to eq(1)
    end

    [["tenant0", -> { "tenant1" }], ["tenant1", -> { Tenant.new(name: "tenant1") }]].each do |id, make_tenant|
      it "test_delete_by_id_tenant[#{id}]" do
        tenant = make_tenant.call
        collection = mt_collection
        collection.tenants.create(tenant)
        tenant1 = collection.with_tenant(tenant)
        uuid = tenant1.data.insert({})
        expect(tenant1.query.fetch_object_by_id(uuid)).not_to be_nil
        expect(tenant1.data.delete_by_id(uuid)).to be true
        expect(tenant1.query.fetch_object_by_id(uuid)).to be_nil
      end
    end

    it "test_insert_many_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "Name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "tenant1"), Tenant.new(name: "tenant2")])
      tenant1 = collection.with_tenant("tenant1")
      tenant2 = collection.with_tenant("tenant2")

      ret = tenant1.data.insert_many(
        [
          DataObject.new(properties: { "name" => "some name" }, vector: [1, 2, 3]),
          DataObject.new(properties: { "name" => "some other name" }, uuid: SecureRandom.uuid)
        ]
      )
      expect(ret.has_errors).to be false
      obj1 = tenant1.query.fetch_object_by_id(ret.uuids[0])
      obj2 = tenant1.query.fetch_object_by_id(ret.uuids[1])
      expect(obj1.properties["name"]).to eq("some name")
      expect(obj2.properties["name"]).to eq("some other name")
      expect(tenant2.query.fetch_object_by_id(ret.uuids[0])).to be_nil
      expect(tenant2.query.fetch_object_by_id(ret.uuids[1])).to be_nil
    end

    it "test_replace_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "Name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "tenant1"), Tenant.new(name: "tenant2")])
      tenant1 = collection.with_tenant("tenant1")
      tenant2 = collection.with_tenant("tenant2")

      uuid = tenant1.data.insert({ "name" => "some name" })
      tenant1.data.replace(properties: { "name" => "other name" }, uuid: uuid)
      expect(tenant1.query.fetch_object_by_id(uuid).properties["name"]).to eq("other name")
      expect(tenant2.query.fetch_object_by_id(uuid)).to be_nil
    end

    it "test_tenants_update" do
      collection = collection_factory(
        properties: [Config::Property.new(name: "Name", data_type: Config::DataType::TEXT)],
        vectorizer_config: Config::Configure::Vectorizer.none
      )
      uuid = collection.data.insert({ "name" => "some name" })
      collection.data.update(properties: { "name" => "other name" }, uuid: uuid, vector: [1, 2, 3])
      obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
      expect(obj.properties["name"]).to eq("other name")
      expect(obj.vector["default"]).to eq([1, 2, 3])
    end

    it "test_update_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "Name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "tenant1"), Tenant.new(name: "tenant2")])
      tenant1 = collection.with_tenant("tenant1")
      tenant2 = collection.with_tenant("tenant2")

      uuid = tenant1.data.insert({ "name" => "some name" })
      tenant1.data.update(properties: { "name" => "other name" }, uuid: uuid)
      expect(tenant1.query.fetch_object_by_id(uuid).properties["name"]).to eq("other name")
      expect(tenant2.query.fetch_object_by_id(uuid)).to be_nil
    end

    it "test_tenants" do
      collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                      multi_tenancy_config: Config::Configure.multi_tenancy)

      collection.tenants.create([Tenant.new(name: "tenant1"), Tenant.new(name: "tenant2")])

      tenants = collection.tenants.get
      expect(tenants.length).to eq(2)
      expect(tenants["tenant1"]).to be_a(Tenant)
      expect(tenants["tenant2"]).to be_a(Tenant)
      expect(tenants["tenant1"].name).to eq("tenant1")
      expect(tenants["tenant2"].name).to eq("tenant2")

      if client_factory.connection.weaviate_version.supports_tenants_get_grpc
        tenants = collection.tenants.get_by_names(["tenant2"])
        expect(tenants.length).to eq(1)
        expect(tenants["tenant2"]).to be_a(Tenant)
        expect(tenants["tenant2"].name).to eq("tenant2")
      else
        expect do
          collection.tenants.get_by_names(["tenant2"])
        end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
      end

      collection.tenants.remove(%w[tenant1 tenant2])

      tenants = collection.tenants.get
      expect(tenants.length).to eq(0)
    end

    it "test_search_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "Tenant1"), Tenant.new(name: "Tenant2")])
      tenant1 = collection.with_tenant("Tenant1")
      tenant2 = collection.with_tenant("Tenant2")
      uuid1 = tenant1.data.insert({ "name" => "some name" })
      objects1 = tenant1.query.bm25("some").objects
      expect(objects1.length).to eq(1)
      expect(objects1[0].uuid).to eq(uuid1)

      objects2 = tenant2.query.bm25("some").objects
      expect(objects2.length).to eq(0)
    end

    it "test_fetch_object_by_id_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "Tenant1"), Tenant.new(name: "Tenant2")])
      tenant1 = collection.with_tenant("Tenant1")
      tenant2 = collection.with_tenant("Tenant2")

      uuid1 = tenant1.data.insert({ "name" => "some name" })
      obj1 = tenant1.query.fetch_object_by_id(uuid1)
      expect(obj1.properties["name"]).to eq("some name")

      obj2 = tenant2.query.fetch_object_by_id(uuid1)
      expect(obj2).to be_nil

      uuid2 = tenant2.data.insert({ "name" => "some other name" })
      obj3 = tenant2.query.fetch_object_by_id(uuid2)
      expect(obj3.properties["name"]).to eq("some other name")

      obj4 = tenant1.query.fetch_object_by_id(uuid2)
      expect(obj4).to be_nil
    end

    it "test_fetch_objects_with_tenant" do
      collection = mt_collection(properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)])

      collection.tenants.create([Tenant.new(name: "Tenant1"), Tenant.new(name: "Tenant2")])
      tenant1 = collection.with_tenant("Tenant1")
      tenant2 = collection.with_tenant("Tenant2")

      tenant1.data.insert({ "name" => "some name" })
      objects = tenant1.query.fetch_objects.objects
      expect(objects.length).to eq(1)
      expect(objects[0].properties["name"]).to eq("some name")

      objects = tenant2.query.fetch_objects.objects
      expect(objects.length).to eq(0)

      tenant2.data.insert({ "name" => "some other name" })
      objects = tenant2.query.fetch_objects.objects
      expect(objects.length).to eq(1)
      expect(objects[0].properties["name"]).to eq("some other name")
    end

    it "test_exist_with_tenant" do
      collection = mt_collection
      collection.tenants.create([Tenant.new(name: "Tenant1"), Tenant.new(name: "Tenant2")])

      uuid1 = collection.with_tenant("Tenant1").data.insert({})
      uuid2 = collection.with_tenant("Tenant2").data.insert({})

      expect(collection.with_tenant("Tenant1").data.exists(uuid1)).to be true
      expect(collection.with_tenant("Tenant2").data.exists(uuid1)).to be false
      expect(collection.with_tenant("Tenant2").data.exists(uuid2)).to be true
      expect(collection.with_tenant("Tenant1").data.exists(uuid2)).to be false
    end

    it "test_tenant_with_activity" do
      collection = mt_collection

      recwarn = capture_warnings do
        collection.tenants.create(
          [
            Tenant.new(name: "1", activity_status: TenantActivityStatus::HOT),
            Tenant.new(name: "2", activity_status: TenantActivityStatus::COLD),
            Tenant.new(name: "3", activity_status: TenantActivityStatus::ACTIVE),
            Tenant.new(name: "4", activity_status: TenantActivityStatus::INACTIVE),
            Tenant.new(name: "5")
          ]
        )
      end
      expect(recwarn.length).to eq(2)
      expect(recwarn.any? { |w| w.include?("HOT is deprecated") }).to be true
      expect(recwarn.any? { |w| w.include?("COLD is deprecated") }).to be true
      tenants = collection.tenants.get
      expect(tenants["1"].activity_status).to eq(TenantActivityStatus::ACTIVE)
      expect(tenants["2"].activity_status).to eq(TenantActivityStatus::INACTIVE)
      expect(tenants["3"].activity_status).to eq(TenantActivityStatus::ACTIVE)
      expect(tenants["4"].activity_status).to eq(TenantActivityStatus::INACTIVE)
      expect(tenants["5"].activity_status).to eq(TenantActivityStatus::ACTIVE)
    end

    it "test_update_tenant" do
      collection = mt_collection
      recwarn = capture_warnings do
        collection.tenants.create(Tenant.new(name: "1", activity_status: TenantActivityStatus::HOT))
      end
      expect(recwarn.length).to eq(1)
      expect(recwarn.any? { |w| w.include?("HOT is deprecated") }).to be true
      tenants = collection.tenants.get
      expect(tenants["1"].activity_status).to eq(TenantActivityStatus::ACTIVE)

      recwarn = capture_warnings do
        collection.tenants.update(Tenant.new(name: "1", activity_status: TenantActivityStatus::COLD))
      end
      expect(recwarn.length).to eq(1)
      expect(recwarn.any? { |w| w.include?("COLD is deprecated") }).to be true
      tenants = collection.tenants.get
      expect(tenants["1"].activity_status).to eq(TenantActivityStatus::INACTIVE)

      collection.tenants.update(Tenant.new(name: "1", activity_status: TenantActivityStatus::ACTIVE))
      tenants = collection.tenants.get
      expect(tenants["1"].activity_status).to eq(TenantActivityStatus::ACTIVE)

      collection.tenants.update(Tenant.new(name: "1", activity_status: TenantActivityStatus::INACTIVE))
      tenants = collection.tenants.get
      expect(tenants["1"].activity_status).to eq(TenantActivityStatus::INACTIVE)
    end

    it "test_tenant_exists" do
      collection = mt_collection
      tenant = Tenant.new(name: "1")
      collection.tenants.create([tenant])

      if client_factory.connection.weaviate_version.is_lower_than(1, 25, 0)
        expect do
          collection.tenants.exists(tenant.name)
        end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
      else
        expect(collection.tenants.exists(tenant.name)).to be true
        expect(collection.tenants.exists(tenant)).to be true
        expect(collection.tenants.exists("2")).to be false
      end
    end

    tenant_variants = lambda do |name|
      [["#{name}0", -> { name }], ["#{name}1", -> { Tenant.new(name: name) }]]
    end
    # Python stacks three parametrize decorators; pytest ids are tenant3-tenant2-tenant1.
    tenant_variants.call("tenant3").each do |id3, make3|
      tenant_variants.call("tenant2").each do |id2, make2|
        tenant_variants.call("tenant1").each do |id1, make1|
          it "test_tenant_get_by_name[#{id3}-#{id2}-#{id1}]" do
            tenant1 = make1.call
            tenant2 = make2.call
            tenant3 = make3.call
            collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                            multi_tenancy_config: Config::Configure.multi_tenancy)

            collection.tenants.create([Tenant.new(name: "tenant1")])

            if client_factory.connection.weaviate_version.supports_tenants_get_grpc
              tenant = collection.tenants.get_by_name(tenant1)
              expect(tenant).not_to be_nil
              expect(tenant.name).to eq("tenant1")

              tenant = collection.tenants.get_by_name(tenant2)
              expect(tenant).to be_nil
            else
              expect do
                collection.tenants.get_by_name(tenant3)
              end.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
            end
          end
        end
      end
    end

    it "test_autotenant_toggling" do
      collection = mt_collection
      skip_unless_version!(client_factory, 1, 25, 0, "Auto-tenant creation")

      expect(collection.config.get.multi_tenancy_config.auto_tenant_creation).to be false

      collection.config.update(
        multi_tenancy_config: Config::Reconfigure.multi_tenancy(auto_tenant_creation: true)
      )
      expect(collection.config.get.multi_tenancy_config.auto_tenant_creation).to be true

      collection.config.update(
        multi_tenancy_config: Config::Reconfigure.multi_tenancy(auto_tenant_creation: false)
      )
      expect(collection.config.get.multi_tenancy_config.auto_tenant_creation).to be false
    end

    [
      ["tenant", -> { "tenant" }],
      ["tenants1", -> { Tenant.new(name: "tenant") }],
      ["tenants2", -> { TenantCreate.new(name: "tenant") }],
      ["tenants3", -> { ["tenant"] }],
      ["tenants4", -> { [Tenant.new(name: "tenant")] }],
      ["tenants5", -> { [TenantCreate.new(name: "tenant")] }]
    ].each do |id, make_tenants|
      it "test_tenants_create[#{id}]" do
        collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                        multi_tenancy_config: Config::Configure.multi_tenancy)

        collection.tenants.create(make_tenants.call)
        t = collection.tenants.get
        expect(t.length).to eq(1)
        expect(t["tenant"].name).to eq("tenant")
      end
    end

    [
      ["tenant", -> { "tenant" }],
      ["tenants1", -> { Tenant.new(name: "tenant") }],
      ["tenants2", -> { ["tenant"] }],
      ["tenants3", -> { [Tenant.new(name: "tenant")] }]
    ].each do |id, make_tenants|
      it "test_tenants_remove[#{id}]" do
        collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                        multi_tenancy_config: Config::Configure.multi_tenancy)

        collection.tenants.create(%w[tenant tenantt])
        collection.tenants.remove(make_tenants.call)
        t = collection.tenants.get
        expect(t).not_to include("tenant")
        expect(t).to include("tenantt")
      end
    end

    [
      ["tenants0", -> { Tenant.new(name: "1", activity_status: TenantActivityStatus::FROZEN) }],
      ["tenants1", -> { [Tenant.new(name: "4", activity_status: TenantActivityStatus::FROZEN)] }]
    ].each do |id, make_tenants|
      it "test_tenants_create_with_read_only_activity_status[#{id}]" do
        collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                        multi_tenancy_config: Config::Configure.multi_tenancy)
        expect do
          collection.tenants.create(make_tenants.call)
        end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
      end
    end

    [
      ["tenants0", -> { Tenant.new(name: "1", activity_status: TenantActivityStatus::OFFLOADING) }],
      ["tenants1", -> { Tenant.new(name: "1", activity_status: TenantActivityStatus::ONLOADING) }],
      ["tenants2", lambda {
        [Tenant.new(name: "1", activity_status: TenantActivityStatus::OFFLOADING),
         Tenant.new(name: "2", activity_status: TenantActivityStatus::ONLOADING)]
      }]
    ].each do |id, make_tenants|
      it "test_tenants_update_with_read_only_activity_status[#{id}]" do
        collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                        multi_tenancy_config: Config::Configure.multi_tenancy)
        expect do
          collection.tenants.update(make_tenants.call)
        end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
      end
    end

    it "test_tenants_create_and_update_1001_tenants" do
      collection = collection_factory(vectorizer_config: Config::Configure::Vectorizer.none,
                                      multi_tenancy_config: Config::Configure.multi_tenancy)

      tenants = Array.new(1001) { |i| TenantCreate.new(name: "tenant#{i}") }

      collection.tenants.create(tenants)
      t = collection.tenants.get
      expect(t.length).to eq(1001)
      expect(t.values.all? { |tenant| tenant.activity_status == TenantActivityStatus::ACTIVE }).to be true

      tenants = Array.new(1001) { |i| Tenant.new(name: "tenant#{i}", activity_status: TenantActivityStatus::INACTIVE) }
      collection.tenants.update(tenants)
      t = collection.tenants.get
      expect(t.length).to eq(1001)
      expect(t.values.all? { |tenant| tenant.activity_status == TenantActivityStatus::INACTIVE }).to be true
    end

    it "test_tenants_auto_tenant_creation" do
      collection_factory(name: "dummy")
      skip_unless_version!(client_factory, 1, 25, 0, "Auto-tenant creation")

      collection = collection_factory(
        properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)],
        vectorizer_config: Config::Configure::Vectorizer.none,
        multi_tenancy_config: Config::Configure.multi_tenancy(auto_tenant_creation: true)
      )

      collection.with_tenant("tenant").data.insert_many(
        Array.new(101) { DataObject.new(properties: { "name" => "some name" }) }
      )

      client = client_factory
      client.batch.fixed_size(batch_size: 101) do |batch|
        101.times do |i|
          batch.add_object(collection: collection.name, properties: { "name" => "some name" }, tenant: "tenant-#{i}")
        end
      end
      expect(client.batch.failed_objects.length).to eq(0)
    end

    it "test_tenants_deactivate_then_activate" do
      collection = mt_collection(properties: [Config::Property.new(name: "name", data_type: Config::DataType::TEXT)])

      t = Tenant.new(name: "tenant1")
      collection.tenants.create([t])
      tenant1 = collection.with_tenant(t)

      tenant1.data.insert({ "name" => "some name" })
      expect(tenant1.query.fetch_objects.objects[0].properties["name"]).to eq("some name")

      collection.tenants.deactivate(t)
      expect(collection.tenants.get["tenant1"].activity_status).to eq(TenantActivityStatus::INACTIVE)

      collection.tenants.activate(t)
      expect(tenant1.query.fetch_objects.objects[0].properties["name"]).to eq("some name")
    end
  end
end
