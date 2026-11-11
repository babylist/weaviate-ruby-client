# frozen_string_literal: true

# Port of integration/test_collection_batch.py
RSpec.describe "collection batch", :integration do
  include Batch3Helpers

  query = Weaviate::Classes::Query
  data = Weaviate::Classes::Data
  tenant_cls = Weaviate::Classes::Tenants::Tenant
  cross_reference = Weaviate::Outputs::Query::CrossReference

  uuid1 = "806827e0-2b31-43ca-9269-24fa95a221f9"
  uuid2 = "8ad0d33c-8db1-4437-87f3-72161ca2a51a"
  uuid3 = "83d99755-9deb-4b16-8431-d1dff4ab0a75"
  uuid4 = "385c992b-452a-4f71-a5d9-b161f51b540d"
  uuid5 = "0a4d16b3-c418-40d3-a6b7-51f87c7a603b"
  uuid6 = "c8a201b6-fdd2-48d1-a8ee-289a540b1b4b"

  after do
    # test_non_existant_collection may auto-create this collection
    client_factory.collections.delete("DoesNotExist") if @created_does_not_exist
  end

  # Python's MockNumpyTorch / MockTensorFlow become array-like objects responding to `to_a`.
  vectors = {
    "vector0" => nil,
    "vector1" => [1, 2, 3],
    "vector2" => Batch3Helpers::MockArrayLike.new([1, 2, 3]),
    "vector3" => Batch3Helpers::MockArrayLike.new([1, 2, 3])
  }
  # uuid.UUID / str / hex: Ruby UUIDs are Strings, the hex form has no dashes.
  uuids = { "uuid0" => nil, "uuid1" => uuid1, "uuid2" => uuid2, "uuid3" => uuid3.delete("-") }

  uuids.each do |uuid_label, uuid|
    vectors.each do |vector_label, vector|
      it "test_add_object[#{uuid_label}-#{vector_label}]" do
        collection = batch_collection

        collection.batch.dynamic do |batch|
          batch.add_object(uuid: uuid, vector: vector)
        end
        expect(collection.batch.failed_objects.length).to eq(0)
        expect(collection.batch.failed_references.length).to eq(0)
        objs = collection.query.fetch_objects.objects
        expect(objs.length).to eq(1)
      end
    end
  end

  { "to_uuid0" => uuid4.delete("-"), "to_uuid1" => uuid5, "to_uuid2" => uuid6 }.each do |to_label, to_uuid|
    { "from_uuid0" => uuid1, "from_uuid1" => uuid2, "from_uuid2" => uuid3.delete("-") }.each do |from_label, from_uuid|
      it "test_add_reference[#{to_label}-#{from_label}]" do
        collection = batch_collection

        collection.batch.dynamic do |batch|
          batch.add_object(uuid: from_uuid)
          batch.add_object(uuid: to_uuid)
          batch.add_reference(from_uuid: from_uuid, from_property: "test", to: to_uuid)
        end
        expect(collection.batch.failed_objects.length).to eq(0)
        expect(collection.batch.failed_references.length).to eq(0)
        objs = collection.query.fetch_objects.objects
        obj = collection.query.fetch_object_by_id(from_uuid,
                                                  return_references: query::QueryReference.new(link_on: "test"))
        expect(objs.length).to eq(2)
        expect(obj.references["test"]).to be_a(cross_reference)
      end
    end
  end

  it "test_add_object_batch_with_tenant" do
    mt_collection = batch_collection(multi_tenancy: true)

    mt_collection.tenants.create(Array.new(5) { |i| tenant_cls.new(name: "tenant#{i}") })
    5.times do |i|
      col = mt_collection.with_tenant("tenant#{i % 5}")
      col.batch.fixed_size(batch_size: 10, concurrent_requests: 1) do |batch|
        batch.add_object(properties: { "name" => "tenant#{i % 5}" })
      end
      expect(col.batch.failed_objects.length).to eq(0)
      expect(col.batch.failed_references.length).to eq(0)
    end
    objs = mt_collection.with_tenant("tenant1").query.fetch_objects.objects
    expect(objs.length).to eq(1)
    objs.each { |obj| expect(obj.properties["name"]).to eq("tenant1") }
  end

  it "test_add_ref_batch_with_tenant" do
    mt_collection = batch_collection(multi_tenancy: true)

    mt_collection.tenants.create(Array.new(5) { |i| tenant_cls.new(name: "tenant#{i}") })

    batching = mt_collection.with_tenant("tenant1")
    obj_uuid0 = random_uuid
    obj_uuid1 = random_uuid
    batching.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => "one" }, uuid: obj_uuid0)
      batch.add_object(properties: { "name" => "two" }, uuid: obj_uuid1)

      # add refs between classes for all tenants
      batch.add_reference(
        from_property: "test", from_uuid: obj_uuid1,
        to: data::ReferenceToMulti.new(uuids: obj_uuid0, target_collection: mt_collection.name)
      )
      batch.add_reference(
        from_property: "test", from_uuid: obj_uuid0,
        to: data::ReferenceToMulti.new(uuids: obj_uuid1, target_collection: mt_collection.name)
      )
      # target collection required when inserting references into multi-tenancy collections
    end
    expect(batching.batch.failed_objects.length).to eq(0)
    expect(batching.batch.failed_references.length).to eq(0)
    ret_obj = mt_collection.with_tenant("tenant1").query.fetch_object_by_id(
      obj_uuid0, return_references: query::QueryReference.new(link_on: "test")
    )
    expect(ret_obj.properties["name"]).to eq("one")
    expect(ret_obj.references["test"]).to be_a(cross_reference)
    expect(ret_obj.references["test"].objects[0].uuid).to eq(obj_uuid1)
  end

  it "test_error_reset" do
    col = batch_collection
    col.batch.fixed_size(batch_size: 1) do |batch|
      batch.add_object(properties: { "name" => 1 })
      batch.add_object(properties: { "name" => "correct" })

      # make sure that errors are processed
      batch.flush
      expect(col.batch.failed_objects.length).to eq(0) # error is still private
      expect(batch.number_errors).to eq(1)
    end

    errs = col.batch.failed_objects
    expect(errs.length).to eq(1)
    expect(errs[0].object_.properties).not_to be_nil
    expect(errs[0].object_.properties["name"]).to eq(1)

    col.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => 2 })
      batch.add_object(properties: { "name" => "correct" })
    end

    errs2 = col.batch.failed_objects
    expect(errs2.length).to eq(1)
    expect(errs2[0].object_.properties).not_to be_nil
    expect(errs2[0].object_.properties["name"]).to eq(2)

    # err still contains original errors
    expect(errs.length).to eq(1)
    expect(errs[0].object_.properties).not_to be_nil
    expect(errs[0].object_.properties["name"]).to eq(1)
  end

  it "test_refs_and_objects" do
    # Test that references are not added before the source object is added.
    col = batch_collection
    uuids_ = Array.new(10) { random_uuid }
    col.batch.fixed_size(batch_size: 1, concurrent_requests: 1) do |batch|
      uuids_.each { |uid| batch.add_object(properties: {}, uuid: uid) }
      batch.add_reference(from_uuid: uuids_[-1], from_property: "test", to: uuids_[-1])
    end

    expect(col.batch.failed_objects.length).to eq(0)
    expect(col.batch.failed_references.length).to eq(0)

    obj = col.query.fetch_object_by_id(uuids_[-1], return_references: query::QueryReference.new(link_on: "test"))
    expect(obj.references).to include("test")
    expect(obj.references["test"].objects[0].uuid).to eq(uuids_[-1])
  end

  it "test_non_existant_collection" do
    collection = collection_factory_get("DoesNotExist")
    @created_does_not_exist = true
    collection.batch.dynamic do |batch|
      batch.add_object(properties: { "name" => 2 })
    end

    # above should not throw - depending on the autoschema config this might create an error or
    # not, so we do not check for errors here
  end

  it "test_batch_one_hundred_thousand_objects_async_collection" do
    skip("the async client is not ported to Ruby")
  end

  it "test_ingest_one_hundred_thousand_data_objects_async" do
    skip("the async client is not ported to Ruby")
  end

  it "test_ingest_one_hundred_thousand_data_objects" do
    col = batch_collection
    skip_unless_version!(client_factory, 1, 36, 0, "Server-side batching")
    nr_objects = 100_000

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results = col.data.ingest(Enumerator.new { |y| nr_objects.times { |i| y << { "name" => "test#{i}" } } })
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts "Time taken to add #{nr_objects} objects: #{elapsed} seconds"
    expect(results.errors.length).to eq(0)
    expect(results.all_responses.length).to eq(nr_objects)
    expect(results.uuids.length).to eq(nr_objects)
    expect(col.length).to eq(nr_objects)
    expect(results.has_errors).to be(false)
    expect(results.errors.length).to eq(0), results.errors.values.map(&:message).inspect
  end
end
