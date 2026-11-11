# frozen_string_literal: true

# Port of integration/test_collection_batch_delete.py
RSpec.describe "collection batch delete", :integration do
  include Batch3Helpers

  config = Weaviate::Classes::Config
  data = Weaviate::Classes::Data
  filter = Weaviate::Classes::Query::Filter
  prop = ->(name, data_type, **kw) { config::Property.new(name: name, data_type: data_type, **kw) }
  dt = config::DataType

  now = Time.now.utc
  later = now + 3600

  uuid1 = SecureRandom.uuid
  uuid2 = SecureRandom.uuid

  [true, false].each do |verbose|
    it "test_verbosity[#{verbose ? "True" : "False"}]" do
      collection = collection_factory(vectorizer_config: config::Configure::Vectorizer.none)

      uuid1_ = collection.data.insert(properties: {})
      uuid2_ = collection.data.insert(properties: {})

      ret = collection.data.delete_many(where: filter.by_id.equal(uuid1_), verbose: verbose, dry_run: false)

      expect(ret.failed).to eq(0)
      expect(ret.matches).to eq(1)
      expect(ret.successful).to eq(1)

      if verbose
        expect(ret.objects).not_to be_nil
        expect(ret.objects.length).to eq(1)
        expect(ret.objects[0].uuid).to eq(uuid1_)
        expect(ret.objects[0].successful).to be_truthy
        expect(ret.objects[0].error).to be_nil
      else
        expect(ret.objects).to be_nil
      end

      expect(collection.length).to eq(1)
      expect(collection.query.fetch_object_by_id(uuid2_)).not_to be_nil
    end
  end

  it "test_batch_delete_with_tenant" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      multi_tenancy_config: config::Configure.multi_tenancy(enabled: true)
    )
    collection.tenants.create([Weaviate::Classes::Tenants::Tenant.new(name: "tenant1"),
                               Weaviate::Classes::Tenants::Tenant.new(name: "tenant2")])

    uuid1_ = collection.with_tenant("tenant1").data.insert(properties: {})
    uuid2_ = collection.with_tenant("tenant2").data.insert(properties: {})

    expect do
      collection.data.delete_many(where: filter.by_id.contains_any([uuid1_, uuid2_]))
    end.to raise_error(Weaviate::Exceptions::WeaviateQueryException)

    ret = collection.with_tenant("tenant1").data.delete_many(where: filter.by_id.contains_any([uuid1_, uuid2_]))
    expect(ret.failed).to eq(0)
    expect(ret.matches).to eq(1)
    expect(ret.successful).to eq(1)

    expect(collection.with_tenant("tenant1").length).to eq(0)
    expect(collection.with_tenant("tenant2").length).to eq(1)
  end

  [true, false].each do |dry_run|
    it "test_dry_run[#{dry_run ? "True" : "False"}]" do
      collection = collection_factory(vectorizer_config: config::Configure::Vectorizer.none)
      uuid1_ = collection.data.insert(properties: {})
      uuid2_ = collection.data.insert(properties: {})

      ret = collection.data.delete_many(where: filter.by_id.equal(uuid1_), dry_run: dry_run)

      expect(ret.failed).to eq(0)
      expect(ret.matches).to eq(1)
      expect(ret.successful).to eq(1)
      expect(ret.objects).to be_nil

      if dry_run
        expect(collection.length).to eq(2)
        expect(collection.query.fetch_object_by_id(uuid1_)).not_to be_nil
      else
        expect(collection.length).to eq(1)
        expect(collection.query.fetch_object_by_id(uuid1_)).to be_nil
      end

      expect(collection.query.fetch_object_by_id(uuid2_)).not_to be_nil
    end
  end

  it "test_delete_by_time_metadata" do
    collection = collection_factory(
      inverted_index_config: config::Configure.inverted_index(index_timestamps: true),
      vectorizer_config: config::Configure::Vectorizer.none
    )

    uuid1_ = collection.data.insert(properties: {})
    uuid2_ = collection.data.insert(properties: {})

    obj1 = collection.query.fetch_object_by_id(uuid1_)

    collection.data.delete_many(where: filter.by_creation_time.less_or_equal(obj1.metadata.creation_time))

    expect(collection.length).to eq(1)
    expect(collection.query.fetch_object_by_id(uuid2_)).not_to be_nil
  end

  it "test_delete_many_or" do
    collection = collection_factory(
      properties: [prop.call("Name", dt::TEXT), prop.call("Age", dt::INT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    collection.data.insert_many(
      [
        data::DataObject.new(properties: { "age" => 10, "name" => "Timmy" }, uuid: random_uuid),
        data::DataObject.new(properties: { "age" => 20, "name" => "Tim" }, uuid: random_uuid),
        data::DataObject.new(properties: { "age" => 30, "name" => "Timothy" }, uuid: random_uuid)
      ]
    )
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(3)

    collection.data.delete_many(where: filter.by_property("age").equal(10) | filter.by_property("age").equal(30))
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["age"]).to eq(20)
    expect(objects[0].properties["name"]).to eq("Tim")
  end

  it "test_delete_many_return" do
    collection = collection_factory(
      properties: [prop.call("Name", dt::TEXT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    collection.data.insert_many([data::DataObject.new(properties: { "name" => "delet me" }, uuid: random_uuid)])
    ret = collection.data.delete_many(where: filter.by_property("name").equal("delet me"))
    expect(ret.failed).to eq(0)
    expect(ret.matches).to eq(1)
    expect(ret.objects).to be_nil
    expect(ret.successful).to eq(1)
  end

  it "test_delete_many_and" do
    collection = collection_factory(
      properties: [prop.call("Name", dt::TEXT), prop.call("Age", dt::INT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    collection.data.insert_many(
      [
        data::DataObject.new(properties: { "age" => 10, "name" => "Timmy" }, uuid: random_uuid),
        data::DataObject.new(properties: { "age" => 10, "name" => "Tommy" }, uuid: random_uuid)
      ]
    )
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(2)

    collection.data.delete_many(where: filter.by_property("age").equal(10) & filter.by_property("name").equal("Timmy"))

    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["age"]).to eq(10)
    expect(objects[0].properties["name"]).to eq("Tommy")
  end

  obj = ->(props, **kw) { data::DataObject.new(properties: props, uuid: kw.fetch(:uuid) { SecureRandom.uuid }, **kw.except(:uuid)) }

  [
    [[prop.call("text", dt::TEXT)], [obj.call({ "text" => "text" })], filter.by_property("text").equal("text"), 0],
    [[prop.call("text", dt::TEXT)], [obj.call({ "text" => "there is some text in here" })],
     filter.by_property("text").like("text"), 0],
    [[prop.call("text", dt::TEXT)], [obj.call({ "text" => "banana" })], filter.by_property("text").like("ba*"), 0],
    [[prop.call("texts", dt::TEXT_ARRAY)], [obj.call({ "texts" => %w[text1 text2] })],
     filter.by_property("texts").contains_all(%w[text1 text2]), 0],
    [[prop.call("texts", dt::TEXT_ARRAY)], [obj.call({ "texts" => ["text1"] }), obj.call({ "texts" => ["text2"] })],
     filter.by_property("texts").contains_any(["text1"]), 1],
    [[prop.call("int", dt::INT)], [obj.call({ "int" => 10 })], filter.by_property("int").equal(10), 0],
    [[prop.call("int", dt::INT)], [obj.call({ "int" => 10 })], filter.by_property("int").greater_than(5), 0],
    [[prop.call("int", dt::INT)], [obj.call({ "int" => 10 })], filter.by_property("int").less_than(15), 0],
    [[prop.call("int", dt::INT)], [obj.call({ "int" => 10 }), obj.call({ "int" => 15 })],
     filter.by_property("int").greater_or_equal(10), 0],
    [[prop.call("int", dt::INT)], [obj.call({ "int" => 10 }), obj.call({ "int" => 5 })],
     filter.by_property("int").less_or_equal(10), 0],
    [[prop.call("ints", dt::INT_ARRAY)], [obj.call({ "ints" => [1, 2] })],
     filter.by_property("ints").contains_all([1, 2]), 0],
    [[prop.call("ints", dt::INT_ARRAY)], [obj.call({ "ints" => [1] }), obj.call({ "ints" => [2] })],
     filter.by_property("ints").contains_any([1]), 1],
    [[prop.call("float", dt::NUMBER)], [obj.call({ "float" => 1.0 })], filter.by_property("float").equal(1.0), 0],
    [[prop.call("floats", dt::NUMBER_ARRAY)], [obj.call({ "floats" => [1.0, 2.0] })],
     filter.by_property("floats").contains_all([1.0, 2.0]), 0],
    [[prop.call("floats", dt::NUMBER_ARRAY)], [obj.call({ "floats" => [1.0] }), obj.call({ "floats" => [2.0] })],
     filter.by_property("floats").contains_any([1.0]), 1],
    # issue here, doing .greater_than(5) interprets valueInt instead of valueNumber and fails the request
    [[prop.call("float", dt::NUMBER)], [obj.call({ "float" => 10.0 }), obj.call({ "float" => 5.0 })],
     filter.by_property("float").greater_than(5.0), 1],
    [[prop.call("bool", dt::BOOL)], [obj.call({ "bool" => true }), obj.call({ "bool" => false })],
     filter.by_property("bool").equal(true), 1],
    [[prop.call("bools", dt::BOOL_ARRAY)], [obj.call({ "bools" => [true, false] })],
     filter.by_property("bools").contains_all([true, false]), 0],
    [[prop.call("bools", dt::BOOL_ARRAY)], [obj.call({ "bools" => [true] }), obj.call({ "bools" => [false] })],
     filter.by_property("bools").contains_any([true]), 1],
    [[prop.call("date", dt::DATE)], [obj.call({ "date" => now })], filter.by_property("date").equal(now), 0],
    [[prop.call("dates", dt::DATE_ARRAY)], [obj.call({ "dates" => [now, later] })],
     filter.by_property("dates").contains_all([now, later]), 0],
    [[prop.call("dates", dt::DATE_ARRAY)], [obj.call({ "dates" => [now] }), obj.call({ "dates" => [later] })],
     filter.by_property("dates").contains_any([now]), 1],
    [[prop.call("uuid", dt::UUID)], [obj.call({ "uuid" => uuid1 })], filter.by_property("uuid").equal(uuid1), 0],
    [[prop.call("uuids", dt::UUID_ARRAY)], [obj.call({ "uuids" => [uuid1, uuid2] })],
     filter.by_property("uuids").contains_all([uuid1, uuid2]), 0],
    [[prop.call("uuids", dt::UUID_ARRAY)], [obj.call({ "uuids" => [uuid1] }), obj.call({ "uuids" => [uuid2] })],
     filter.by_property("uuids").contains_any([uuid1]), 1],
    [[prop.call("text", dt::TEXT, tokenization: config::Tokenization::FIELD)],
     [data::DataObject.new(properties: { "text" => "some name" }, vector: [1, 2, 3]),
      obj.call({ "text" => "some other name" })],
     filter.by_property("text").equal("some name"), 1],
    [[prop.call("text", dt::TEXT, tokenization: config::Tokenization::FIELD)],
     [data::DataObject.new(properties: { "text" => "some name" }, vector: [1, 2, 3]),
      obj.call({ "text" => "some other name" })],
     filter.by_property("text").equal("some other name"), 1],
    [[prop.call("text", dt::TEXT), prop.call("int", dt::INT)],
     [obj.call({ "text" => "Loads of money", "int" => 60 }), obj.call({ "text" => "Lots of money", "int" => 40 })],
     filter.by_property("text").equal("money"), 0],
    [[prop.call("text", dt::TEXT), prop.call("int", dt::INT)],
     [obj.call({ "int" => 10 }), obj.call({ "text" => "I am ageless" })],
     filter.by_property("int").is_none(true), 1],
    [[prop.call("text", dt::TEXT), prop.call("int", dt::INT)],
     [obj.call({ "int" => 10 }, uuid: uuid1), obj.call({ "text" => "I am ageless" }, uuid: uuid2)],
     filter.by_id.equal(uuid1), 1]
  ].each_with_index do |(properties, inserts, where, expected_len), i|
    it "test_delete_many_simple[properties#{i}-inserts#{i}-where#{i}-#{expected_len}]" do
      collection = collection_factory(
        properties: properties,
        inverted_index_config: config::Configure.inverted_index(index_null_state: true),
        vectorizer_config: config::Configure::Vectorizer.none
      )
      collection.data.insert_many(inserts)
      expect(collection.query.fetch_objects.objects.length).to eq(inserts.length)

      collection.data.delete_many(where: where)
      objects = collection.query.fetch_objects.objects
      expect(objects.length).to eq(expected_len)
    end
  end

  def source_with_refs(to)
    config = Weaviate::Classes::Config
    data = Weaviate::Classes::Data
    uuid_to1 = to.data.insert(properties: {})
    uuid_to2 = to.data.insert(properties: {})

    source = collection_factory(
      name: "source", references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)]
    )
    source.config.add_reference(
      config::ReferenceProperty::MultiTarget.new(name: "ref_self", target_collections: [source.name, to.name])
    )

    uuid_source1 = source.data.insert(properties: {})
    uuid_source2 = source.data.insert(properties: {})
    source.data.reference_add(uuid_source1, from_property: "ref", to: uuid_to1)
    source.data.reference_add(uuid_source2, from_property: "ref", to: uuid_to2)
    source.data.reference_add(
      uuid_source1, from_property: "ref_self",
                    to: data::ReferenceToMulti.new(uuids: uuid_source2, target_collection: source.name)
    )
    source.data.reference_add(
      uuid_source2, from_property: "ref_self",
                    to: data::ReferenceToMulti.new(uuids: uuid_source1, target_collection: source.name)
    )
    [source, uuid_to1, uuid_source1, uuid_source2]
  end

  it "test_batch_delete_with_refs" do
    to = collection_factory(name: "To")
    source, uuid_to1, _uuid_source1, uuid_source2 = source_with_refs(to)

    ret = source.data.delete_many(
      where: filter.by_ref_multi_target("ref_self", target_collection: source.name)
                   .by_ref("ref")
                   .by_id
                   .equal(uuid_to1),
      verbose: true
    )
    expect(ret.objects[0].uuid).to eq(uuid_source2)
  end

  [true, false].each do |update_or_creation|
    it "test_delete_by_time_metadata_with_ref[#{update_or_creation ? "True" : "False"}]" do
      to = collection_factory(name: "To", inverted_index_config: config::Configure.inverted_index(index_timestamps: true))
      source, uuid_to1, uuid_source1, uuid_source2 = source_with_refs(to)

      obj1 = to.query.fetch_object_by_id(uuid_to1)

      if update_or_creation
        source.data.delete_many(
          where: filter.by_ref_multi_target("ref_self", target_collection: source.name)
                       .by_ref("ref")
                       .by_creation_time
                       .less_or_equal(obj1.metadata.creation_time)
        )
      else
        source.data.delete_many(
          where: filter.by_ref_multi_target("ref_self", target_collection: source.name)
                       .by_ref("ref")
                       .by_update_time
                       .less_or_equal(obj1.metadata.creation_time)
        )
      end

      expect(source.length).to eq(1)
      expect(source.query.fetch_object_by_id(uuid_source1)).not_to be_nil
      expect(source.query.fetch_object_by_id(uuid_source2)).to be_nil
    end
  end

  it "test_delete_many_with_consistency_level" do
    collection = collection_factory(
      properties: [prop.call("text", dt::TEXT), prop.call("int", dt::INT)]
    ).with_consistency_level(config::ConsistencyLevel::ALL)
    collection.data.insert_many(
      [
        data::DataObject.new(properties: { "int" => 10 }, uuid: uuid1),
        data::DataObject.new(properties: { "text" => "I am ageless" }, uuid: uuid2)
      ]
    )
    expect(collection.query.fetch_objects.objects.length).to eq(2)

    collection.data.delete_many(where: filter.by_id.equal(uuid1))
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(1)
  end
end
