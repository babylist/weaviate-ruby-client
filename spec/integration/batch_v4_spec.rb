# frozen_string_literal: true

require "stringio"

# Port of integration/test_batch_v4.py
RSpec.describe "batch v4", :integration do
  include Batch3Helpers

  query = Weaviate::Classes::Query
  data = Weaviate::Classes::Data
  tenant_cls = Weaviate::Classes::Tenants::Tenant
  shard_cls = Weaviate::Classes::Batch::Shard
  cross_reference = Weaviate::Outputs::Query::CrossReference

  uuid1 = "806827e0-2b31-43ca-9269-24fa95a221f9"
  uuid2 = "8ad0d33c-8db1-4437-87f3-72161ca2a51a"
  uuid3 = "83d99755-9deb-4b16-8431-d1dff4ab0a75"
  uuid4 = "385c992b-452a-4f71-a5d9-b161f51b540d"
  uuid5 = "0a4d16b3-c418-40d3-a6b7-51f87c7a603b"
  uuid6 = "c8a201b6-fdd2-48d1-a8ee-289a540b1b4b"

  def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def shard_status_is(shard, want)
    if shard.per_node_status && !shard.per_node_status.empty?
      shard.per_node_status.values.all? { |status| status == want }
    elsif shard.status
      shard.status == want
    else
      false
    end
  end

  def make_refs(uuids, name)
    refs = []
    uuids.each do |from|
      (uuids - [from]).each do |to|
        refs << { from_uuid: from, from_collection: name, from_property: "test", to: to }
      end
    end
    refs
  end

  it "test_add_objects_in_multiple_batches" do
    client, name = batch_client_factory
    client.batch.rate_limit(requests_per_minute: 50) do |batch|
      batch.add_object(collection: name, properties: {})
    end
    client.batch.dynamic do |batch|
      batch.add_object(collection: name, properties: {})
    end
    client.batch.dynamic do |batch|
      batch.add_object(collection: name, properties: {})
    end
    objs = client.collections.use(name).query.fetch_objects.objects
    expect(objs.length).to eq(3)
  end

  it "test_flushing" do
    # Test that batch is working normally after flushing.
    client, name = batch_client_factory
    client.batch.dynamic do |batch|
      batch.add_object(collection: name, properties: {})
      batch.flush
      objs = client.collections.use(name).query.fetch_objects.objects
      expect(objs.length).to eq(1)
      batch.add_object(collection: name, properties: {})
      batch.add_object(collection: name, properties: {})
    end
    objs = client.collections.use(name).query.fetch_objects.objects
    expect(objs.length).to eq(3)
  end

  # Python's numpy/torch, tensorflow and pandas/polars doubles become array-like objects (`to_a`).
  vectors = {
    "vector0" => nil,
    "vector1" => [1, 2, 3],
    "vector2" => Batch3Helpers::MockArrayLike.new([1, 2, 3]),
    "vector3" => Batch3Helpers::MockArrayLike.new([1, 2, 3]),
    "vector4" => Batch3Helpers::MockArrayLike.new([1, 2, 3])
  }
  # uuid.UUID / str / hex: Ruby UUIDs are Strings, the hex form has no dashes.
  uids = { "uid0" => nil, "uid1" => uuid1, "uid2" => uuid2, "uid3" => uuid3.delete("-") }

  uids.each do |uid_label, uid|
    vectors.each do |vector_label, vector|
      it "test_add_object[#{uid_label}-#{vector_label}]" do
        client, name = batch_client_factory
        client.batch.fixed_size do |batch|
          batch.add_object(collection: name, properties: {}, uuid: uid, vector: vector)
        end
        objs = client.collections.use(name).query.fetch_objects.objects
        expect(objs.length).to eq(1)
      end
    end
  end

  [false, true].each do |to_object_collection|
    { "to_object_uuid0" => uuid4.delete("-"), "to_object_uuid1" => uuid5,
      "to_object_uuid2" => uuid6 }.each do |to_label, to_object_uuid|
      { "from_object_uuid0" => uuid1, "from_object_uuid1" => uuid2,
        "from_object_uuid2" => uuid3.delete("-") }.each do |from_label, from_object_uuid|
        it "test_add_reference[#{to_object_collection ? "True" : "False"}-#{to_label}-#{from_label}]" do
          # Test the `add_reference` method.
          client, name = batch_client_factory
          client.batch.dynamic do |batch|
            batch.add_object(properties: {}, collection: name, uuid: from_object_uuid)
            batch.add_object(properties: {}, collection: name, uuid: to_object_uuid)
            batch.add_reference(
              from_uuid: from_object_uuid,
              from_collection: name,
              from_property: "test",
              to: if to_object_collection
                    data::ReferenceToMulti.new(target_collection: name, uuids: to_object_uuid)
                  else
                    to_object_uuid
                  end
            )
          end
          expect(client.batch.failed_objects.length).to eq(0), client.batch.failed_objects.map(&:message).inspect
          expect(client.batch.failed_references.length).to eq(0),
                                                           client.batch.failed_references.map(&:message).inspect
          objs = client.collections.use(name)
                       .query.fetch_objects(return_references: query::QueryReference.new(link_on: "test"))
                       .objects
          obj = client.collections.use(name).query.fetch_object_by_id(
            from_object_uuid, return_references: query::QueryReference.new(link_on: "test")
          )
          expect(objs.length).to eq(2)
          expect(obj.references["test"]).to be_a(cross_reference)
        end
      end
    end
  end

  it "test_add_data_object_and_get_class_shards_readiness" do
    client, name = batch_client_factory
    # Python passes `request.node.name` (the un-capitalised test name); Weaviate capitalises it.
    node_name = name[0].downcase + name[1..]

    client.batch.fixed_size do |batch|
      batch.add_object(properties: {}, collection: node_name)
    end
    statuses = client.batch._get_shards_readiness(shard_cls.new(collection: name))
    expect(statuses.length).to eq(1)
    expect(statuses[0]).to be_truthy
  end

  it "test_add_data_object_with_tenant_and_get_class_shards_readiness" do
    # Test the `add_data_object` method.
    client, name = batch_client_factory(multi_tenant: true)
    client.collections.use(name).tenants.create([tenant_cls.new(name: "tenant1"), tenant_cls.new(name: "tenant2")])
    client.batch.fixed_size do |batch|
      batch.add_object(properties: {}, collection: name, tenant: "tenant1")
    end
    statuses = client.batch._get_shards_readiness(shard_cls.new(collection: name, tenant: "tenant1"))
    expect(statuses.length).to eq(1)
    expect(statuses[0]).to be_truthy
  end

  it "test_add_object_batch_with_tenant" do
    # create two classes and add 5 tenants each
    tenants = Array.new(5) { |i| tenant_cls.new(name: "tenant#{i}") }
    node_name = RSpec.current_example.description
    client, name1 = batch_client_factory(name: "#{node_name}1", multi_tenant: true)
    _, name2 = batch_client_factory(name: "#{node_name}2", multi_tenant: true) # to enable automatic cleanup
    client.collections.use(name1).tenants.create(tenants)
    client.collections.use(name2).tenants.create(tenants)

    nr_objects = 100
    objects = []
    client.batch.dynamic do |batch|
      nr_objects.times do |i|
        obj_uuid = random_uuid
        objects << [obj_uuid, i.odd? ? name1 : name2, "tenant#{i % 5}"]
        batch.add_object(
          collection: i.odd? ? name1 : name2,
          tenant: "tenant#{i % 5}",
          properties: { "name" => "tenant#{i % 5}" },
          uuid: obj_uuid
        )
      end
    end

    objects.each do |obj|
      ret_obj = client.collections.use(obj[1]).with_tenant(obj[2]).query.fetch_object_by_id(obj[0])
      expect(ret_obj.properties["name"]).to eq(obj[2])
    end
  end

  {
    "_from_uuid_to_uuid" => ->(uuid) { uuid },
    "_from_uuid_to_str" => ->(uuid) { uuid.to_s },
    "_from_uuid_to_uuid_list" => ->(uuid) { [uuid] },
    "_from_uuid_to_str_list" => ->(uuid) { [uuid.to_s] }
  }.each do |label, to_ref|
    it "test_add_ref_batch[#{label}]" do
      client, name = batch_client_factory

      nr_objects = 100
      objects_class0 = []
      client.batch.dynamic do |batch|
        nr_objects.times do
          obj_uuid0 = random_uuid
          objects_class0 << obj_uuid0
          batch.add_object(collection: name, uuid: obj_uuid0)
          batch.add_reference(from_property: "test", from_collection: name, from_uuid: obj_uuid0,
                              to: to_ref.call(obj_uuid0))
        end
      end

      collection = client.collections.use(name)
      objects_class0.each do |obj|
        ret_obj = collection.query.fetch_object_by_id(obj, return_references: query::QueryReference.new(link_on: "test"))
        expect(ret_obj).not_to be_nil
        expect(ret_obj.references["test"].objects[0].uuid).to eq(obj)
      end
    end
  end

  it "test_add_ref_batch_with_tenant" do
    client, name = batch_client_factory(multi_tenant: true)
    client.collections.use(name).tenants.create(Array.new(5) { |i| tenant_cls.new(name: "tenant#{i}") })

    nr_objects = 100
    objects_class0 = []
    client.batch.dynamic do |batch|
      nr_objects.times do |i|
        tenant = "tenant#{i % 5}"
        obj_uuid0 = random_uuid
        objects_class0 << [obj_uuid0, tenant]
        batch.add_object(collection: name, tenant: tenant, properties: { "name" => tenant }, uuid: obj_uuid0)

        # add refs between all tenants
        batch.add_reference(
          from_property: "test",
          from_collection: name,
          from_uuid: obj_uuid0,
          to: data::ReferenceToMulti.new(uuids: obj_uuid0, target_collection: name), # workaround for autodetection
          tenant: tenant
        )
      end
    end

    objects_class0.each do |obj|
      ret_obj = client.collections.use(name).with_tenant(obj[1]).query.fetch_object_by_id(
        obj[0], return_properties: "name", return_references: query::QueryReference.new(link_on: "test")
      )
      expect(ret_obj).not_to be_nil
      expect(ret_obj.properties["name"]).to eq(obj[1])
      expect(ret_obj.references["test"].objects[0].uuid).to eq(obj[0])
    end
  end

  {
    "test_add_ten_thousand_data_objects_dynamic" => ->(client, &blk) { client.batch.dynamic(&blk) },
    "test_add_ten_thousand_data_objects_fixed_size" => ->(client, &blk) { client.batch.fixed_size(&blk) },
    "test_add_ten_thousand_data_objects_stream" => ->(client, &blk) { client.batch.stream(concurrency: 1, &blk) }
  }.each do |id, batching_method|
    it "test_add_ten_thousand_data_objects[#{id}]" do
      # Test adding ten thousand data objects.
      client, name = batch_client_factory
      if id == "test_add_ten_thousand_data_objects_stream"
        skip_unless_version!(client, 1, 36, 0, "Server-side batching")
      end
      nr_objects = 100_000

      start = now
      batching_method.call(client) do |batch|
        nr_objects.times { |i| batch.add_object(collection: name, properties: { "name" => "test#{i}" }) }
      end
      puts "Time taken to add #{nr_objects} objects: #{now - start} seconds"
      expect(client.batch.results.objs.errors.length).to eq(0)
      expect(client.batch.results.objs.all_responses.length).to eq(nr_objects)
      expect(client.batch.results.objs.uuids.length).to eq(nr_objects)
      expect(client.collections.use(name).length).to eq(nr_objects)
      expect(client.batch.results.objs.has_errors).to be(false)
      expect(client.batch.failed_objects.length).to eq(0), client.batch.failed_objects.map(&:message).inspect
      client.collections.delete(name)
    end
  end

  it "test_add_one_hundred_objects_and_references_between_all" do
    # Test adding one hundred objects and references between all of them.
    client, name = batch_client_factory
    skip_unless_version!(client, 1, 36, 0, "Server-side batching")
    nr_objects = 100
    uuids = []
    client.batch.stream do |batch|
      nr_objects.times do |i|
        uuids << batch.add_object(collection: name, properties: { "name" => "test#{i}" })
      end
      make_refs(uuids, name).each { |ref| batch.add_reference(**ref) }
    end
    objs = client.collections.use(name)
                 .query.fetch_objects(limit: nr_objects, return_references: query::QueryReference.new(link_on: "test"))
                 .objects
    expect(objs.length).to eq(nr_objects)
    objs.each { |obj| expect(obj.references["test"].objects.length).to eq(nr_objects - 1) }
    client.collections.delete(name)
  end

  it "test_add_1000_objects_with_async_indexing_and_wait" do
    skip_if_native!("needs the async-indexing instance on ports 8090/50061")
    client, name = batch_client_factory(ports: [8090, 50_061])

    nr_objects = 1000
    client.batch.dynamic do |batch|
      nr_objects.times do |i|
        batch.add_object(
          collection: name,
          properties: { "name" => "text#{i}" },
          vector: Array.new(nr_objects) { |j| ((j + i) % nr_objects).to_f / nr_objects }
        )
      end
    end
    expect(client.batch.failed_objects.length).to eq(0)
    client.batch.wait_for_vector_indexing
    ret = client.collections.use(name).aggregate.over_all(total_count: true)
    expect(ret.total_count).to eq(nr_objects)

    shards = client.collections.use(name).config.get_shards
    expect(shard_status_is(shards[0], "READY")).to be(true)
  end

  it "test_add_10000_objects_with_async_indexing_and_dont_wait" do
    skip("Difficult to find numbers that work reliably in the CI")
  end

  it "test_add_1000_tenant_objects_with_async_indexing_and_wait_for_all" do
    skip_if_native!("needs the async-indexing instance on ports 8090/50061")
    client, name = batch_client_factory(ports: [8090, 50_061], multi_tenant: true)
    tenants = Array.new(2) { |i| tenant_cls.new(name: "tenant#{i}") }
    collection = client.collections.use(name)
    collection.tenants.create(tenants)
    nr_objects = 2000

    client.batch.dynamic do |batch|
      nr_objects.times do |i|
        batch.add_object(
          collection: name,
          properties: { "name" => "text#{i}" },
          vector: Array.new(nr_objects) { |j| ((j + i) % nr_objects).to_f / nr_objects },
          tenant: tenants[i % tenants.length].name
        )
      end
    end
    expect(client.batch.failed_objects.length).to eq(0)
    client.batch.wait_for_vector_indexing
    tenants.each do |tenant|
      ret = collection.with_tenant(tenant.name).aggregate.over_all(total_count: true)
      expect(ret.total_count).to eq(nr_objects / tenants.length)
    end

    shards = client.collections.use(name).config.get_shards
    shards.each { |shard| expect(shard_status_is(shard, "READY")).to be(true) }
  end

  it "test_add_1000_tenant_objects_with_async_indexing_and_wait_for_only_one" do
    skip("Difficult to find numbers that work reliably in the CI")
  end

  {
    "test_add_one_object_and_a_self_reference_dynamic" => ->(client, &blk) { client.batch.dynamic(&blk) },
    "test_add_one_object_and_a_self_reference_fixed_size" => ->(client, &blk) { client.batch.fixed_size(&blk) },
    "test_add_one_object_and_a_self_reference_stream" => ->(client, &blk) { client.batch.stream(&blk) }
  }.each do |id, batching_method|
    it "test_add_one_object_and_a_self_reference[#{id}]" do
      # Test adding one object and a self reference.
      client, name = batch_client_factory
      if id == "test_add_one_object_and_a_self_reference_stream"
        skip_unless_version!(client, 1, 36, 0, "Server-side batching")
      end
      uuid = nil
      batching_method.call(client) do |batch|
        uuid = batch.add_object(collection: name, properties: {})
        batch.add_reference(from_uuid: uuid, from_collection: name, from_property: "test", to: uuid)
      end
      obj = client.collections.use(name).query.fetch_object_by_id(
        uuid, return_references: query::QueryReference.new(link_on: "test")
      )
      expect(obj).not_to be_nil
      expect(obj.references["test"].objects[0].uuid).to eq(uuid)
    end
  end

  it "test_multi_threaded_batching" do
    client, name = batch_client_factory
    nr_objects = 1000
    nr_threads = 10

    batch_insert = lambda do |batch|
      nr_objects.times { |i| batch.add_object(collection: name, properties: { "name" => "test#{i}" }) }
    end

    threads = []
    client.batch.dynamic do |batch|
      threads = Array.new(nr_threads) { Thread.new { batch_insert.call(batch) } }
      # Python only joins the ThreadPoolExecutor after the batch context exits (racing the shutdown);
      # the threads are joined inside the block here so every add_object happens before the batch closes.
      threads.each(&:join)
    end
    threads.each(&:value)
    objs = client.collections.use(name).query.fetch_objects(limit: nr_objects * nr_threads).objects
    expect(objs.length).to eq(nr_objects * nr_threads)
  end

  it "test_error_reset" do
    client, name = batch_client_factory
    client.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => 1 }, collection: name)
      batch.add_object(properties: { "name" => "correct" }, collection: name)
    end

    errs = client.batch.failed_objects

    expect(errs.length).to eq(1)
    expect(errs[0].object_.properties).not_to be_nil
    expect(errs[0].object_.properties["name"]).to eq(1)

    client.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => 2 }, collection: name)
      batch.add_object(properties: { "name" => "correct" }, collection: name)
    end

    errs2 = client.batch.failed_objects
    expect(errs2.length).to eq(1)
    expect(errs2[0].object_.properties).not_to be_nil
    expect(errs2[0].object_.properties["name"]).to eq(2)

    # err still contains original errors
    expect(errs.length).to eq(1)
    expect(errs[0].object_.properties).not_to be_nil
    expect(errs[0].object_.properties["name"]).to eq(1)
  end

  it "test_non_existant_collection" do
    client, = batch_client_factory
    client.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => 2 }, collection: "DoesNotExist")
    end
  ensure
    # depending on the autoschema config the add above may have created the collection
    client&.collections&.delete("DoesNotExist")
    # above should not throw - depending on the autoschema config this might create an error or
    # not, so we do not check for errors here
  end

  it "test_number_of_stored_results_in_batch" do
    client, name = batch_client_factory
    client.batch.dynamic do |batch|
      99_999.times { |i| batch.add_object(properties: { "name" => i.to_s }, collection: name) }
    end

    expect(client.batch.results.objs.all_responses.length).to eq(99_999)
    expect(client.batch.results.objs.errors.length).to eq(0)
    expect(client.batch.results.objs.uuids.length).to eq(99_999)
    expect(client.batch.results.objs.uuids.keys.sort).to eq((0...99_999).to_a)

    client.batch.dynamic do |batch|
      100_001.times { |i| batch.add_object(properties: { "name" => i.to_s }, collection: name) }
    end

    expect(client.batch.results.objs.all_responses.length).to eq(100_000)
    expect(client.batch.results.objs.errors.length).to eq(0)
    expect(client.batch.results.objs.uuids.length).to eq(100_000)
    expect(client.batch.results.objs.uuids.keys.sort).to eq((1...100_001).to_a)

    # depending on timings in the event loop, some batches may end before others
    # as such the keys of the uuids dict may not be in order but they are still unique
    # and correspond to the original indices within the batch
  end

  it "test_uuids_keys_and_original_index" do
    client, name = batch_client_factory
    objs = Array.new(100) { |i| [random_uuid, { "name" => i.to_s }] }
    client.batch.dynamic do |batch|
      objs.each { |obj| batch.add_object(uuid: obj[0], properties: obj[1], collection: name) }
    end

    expect(client.batch.results.objs.all_responses.length).to eq(100)
    expect(client.batch.results.objs.errors.length).to eq(0)
    expect(client.batch.results.objs.uuids.length).to eq(100)

    expect(client.batch.results.objs.uuids.keys.map { |k| objs[k][0] })
      .to eq(client.batch.results.objs.uuids.values)
  end

  it "test_batching_error_logs" do
    client, name = batch_client_factory
    if client.connection.weaviate_version.is_at_least(1, 32, 1) # TODO: change to 1.33.0 when released
      skip("Batching error logs do not get emitted by the new server-side batching functionality.")
    end
    io = StringIO.new
    logger = Weaviate::Collections::Batch.logger
    previous_io = logger.io
    logger.io = io
    begin
      client.batch.fixed_size do |batch|
        Array.new(100) { |i| { "name" => i } }.each { |obj| batch.add_object(properties: obj, collection: name) }
      end
    ensure
      logger.io = previous_io
    end
    text = io.string
    # number of objects sent per batch is not fixed for less than 100 objects
    expect(text).to include("Failed to send")
    expect(text).to include("objects in a batch of")
    expect(text).to include(
      "Please inspect client.batch.failed_objects or collection.batch.failed_objects for the failed objects."
    )
  end

  it "test_references_with_to_uuids" do
    # Test that batch waits until the to object is created.
    client, = batch_client_factory
    config = Weaviate::Classes::Config

    client.collections.delete(%w[target source])
    target = client.collections.create(
      "target", multi_tenancy_config: config::Configure.multi_tenancy(enabled: true)
    )
    source = client.collections.create(
      "source",
      references: [config::ReferenceProperty.new(name: "to", target_collection: "target")],
      multi_tenancy_config: config::Configure.multi_tenancy(enabled: true)
    )

    target.tenants.create("tenant-1")
    source.tenants.create("tenant-1")
    from_uuid = source.with_tenant("tenant-1").data.insert(properties: {})
    objs = 20

    client.batch.fixed_size(batch_size: 10, concurrent_requests: 1) do |batch|
      objs.times do
        to = batch.add_object(collection: "target", properties: {}, tenant: "tenant-1")
        batch.add_reference(from_uuid: from_uuid, from_property: "to", to: to, from_collection: "source",
                            tenant: "tenant-1")
      end
    end

    expect(client.batch.failed_references.length).to eq(0), client.batch.failed_references.inspect
    client.collections.delete(%w[target source])
  end

  it "test_add_one_hundred_thousand_objects_async_client" do
    skip("the async client is not ported to Ruby")
  end

  it "test_add_one_hundred_thousand_objects_sync_client" do
    # Test adding one hundred thousand data objects.
    client, name = batch_client_factory
    skip_unless_version!(client, 1, 36, 0, "Server-side batching")
    nr_objects = 100_000

    start = now
    client.batch.stream(concurrency: 1) do |batch|
      nr_objects.times { |i| batch.add_object(collection: name, properties: { "name" => "test#{i}" }) }
    end
    puts "Time taken to add #{nr_objects} objects: #{now - start} seconds"
    expect(client.batch.results.objs.errors.length).to eq(0)
    expect(client.batch.results.objs.all_responses.length).to eq(nr_objects)
    expect(client.batch.results.objs.uuids.length).to eq(nr_objects)
    expect(client.collections.use(name).length).to eq(nr_objects)
    expect(client.batch.results.objs.has_errors).to be(false)
    expect(client.batch.failed_objects.length).to eq(0), client.batch.failed_objects.map(&:message).inspect
    client.collections.delete(name)
  end
end
