# frozen_string_literal: true

# Port of integration/test_collection_filter.py
RSpec.describe "collection filter", :integration do
  include Batch3Helpers

  config = Weaviate::Classes::Config
  query = Weaviate::Classes::Query
  data = Weaviate::Classes::Data
  filter = query::Filter

  now = Time.now.utc
  later = now + 3600
  much_later = now + 86_400

  uuid1 = SecureRandom.uuid
  uuid2 = SecureRandom.uuid
  uuid3 = SecureRandom.uuid
  uuid4 = SecureRandom.uuid

  def expect_uuids(objects, uuids, results)
    expect(objects.length).to eq(results.length)
    expected = results.map { |r| uuids[r] }
    expect(objects.map(&:uuid)).to all(satisfy { |u| expected.include?(u) })
  end

  [
    [filter.by_property("name").equal("Banana"), [0]],
    [filter.by_property("name").not_equal("Banana"), [1, 2]],
    [filter.by_property("name").like("*nana"), [0]]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_filters_text[weaviate_filter#{i}-results#{i}]" do
      collection = collection_factory(
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      uuids = [
        collection.data.insert({ "name" => "Banana" }),
        collection.data.insert({ "name" => "Apple" }),
        collection.data.insert({ "name" => "Mountain" })
      ]

      objects = collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, uuids, results)
    end
  end

  [
    [filter.by_property("texts").like("*nana"), [1]],
    [filter.by_property("texts").equal("banana"), [1]],
    [filter.by_property("ints").equal(3), [1]],
    [filter.by_property("ints").greater_or_equal(3), [1, 2]],
    [filter.by_property("floats").equal(3), [1]],
    [filter.by_property("floats").less_or_equal(3), [0, 1]]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_array_types[weaviate_filter#{i}-results#{i}]" do
      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [
          config::Property.new(name: "texts", data_type: config::DataType::TEXT_ARRAY),
          config::Property.new(name: "ints", data_type: config::DataType::INT_ARRAY),
          config::Property.new(name: "floats", data_type: config::DataType::NUMBER_ARRAY)
        ]
      )

      uuids = [
        collection.data.insert({ "texts" => %w[an apple], "ints" => [1, 2], "floats" => [1.0, 2.0] }),
        collection.data.insert({ "texts" => %w[a banana], "ints" => [2, 3], "floats" => [2.0, 3.0] }),
        collection.data.insert({ "texts" => %w[a text], "ints" => [4, 5], "floats" => [4.0, 5.0] })
      ]

      objects = collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, uuids, results)
    end
  end

  [
    [filter.by_property("int").equal(1), [0]],
    [filter.by_property("int").equal(1.0), [0]],
    [filter.by_property("int").equal(1.2), nil],
    [filter.by_property("float").equal(1), [0]],
    [filter.by_property("float").equal(1.0), [0]]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_filter_with_wrong_types[weaviate_filter#{i}-results#{i}]" do
      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [
          config::Property.new(name: "int", data_type: config::DataType::INT),
          config::Property.new(name: "float", data_type: config::DataType::NUMBER)
        ]
      )

      uuids = [
        collection.data.insert({ "int" => 1, "float" => 1.0 }),
        collection.data.insert({ "int" => 2, "float" => 2.0 }),
        collection.data.insert({ "int" => 3, "float" => 3.0 })
      ]

      if results.nil?
        expect do
          collection.query.fetch_objects(filters: weaviate_filter).objects
        end.to raise_error(Weaviate::Exceptions::WeaviateQueryError)
      else
        objects = collection.query.fetch_objects(filters: weaviate_filter).objects
        expect_uuids(objects, uuids, results)
      end
    end
  end

  [
    [filter.by_property("num").greater_than(1) & filter.by_property("num").less_than(3), [1]],
    [filter.by_property("num").less_or_equal(1) | filter.by_property("num").greater_or_equal(3), [0, 2]],
    [filter.by_property("num").less_or_equal(1) | filter.by_property("num").greater_or_equal(3), [0, 2]],
    [
      (filter.by_property("num").less_or_equal(1) & filter.by_property("num").greater_or_equal(1)) |
        filter.by_property("num").greater_or_equal(3) |
        filter.by_property("num").is_none(true),
      [0, 2, 3]
    ]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_filters_nested[weaviate_filter#{i}-results#{i}]" do
      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [config::Property.new(name: "num", data_type: config::DataType::NUMBER)],
        inverted_index_config: config::Configure.inverted_index(index_null_state: true)
      )

      uuids = [
        collection.data.insert({ "num" => 1.0 }),
        collection.data.insert({ "num" => 2.0 }),
        collection.data.insert({ "num" => 3.0 }),
        collection.data.insert({ "num" => nil })
      ]

      objects = collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, uuids, results)
    end
  end

  it "test_length_filter" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "field", data_type: config::DataType::TEXT)],
      inverted_index_config: config::Configure.inverted_index(index_property_length: true)
    )
    uuids = [
      collection.data.insert({ "field" => "one" }),
      collection.data.insert({ "field" => "two" }),
      collection.data.insert({ "field" => "three" }),
      collection.data.insert({ "field" => "four" })
    ]
    objects = collection.query.fetch_objects(filters: filter.by_property("field", length: true).equal(3)).objects

    expect_uuids(objects, uuids, [0, 1])
  end

  [
    [filter.by_property("number").is_none(true), [3]],
    [filter.by_property("number").is_none(false), [0, 1, 2]]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_filters_comparison[weaviate_filter#{i}-results#{i}]" do
      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [config::Property.new(name: "number", data_type: config::DataType::INT)],
        inverted_index_config: config::Configure.inverted_index(index_null_state: true)
      )

      uuids = [
        collection.data.insert({ "number" => 1 }),
        collection.data.insert({ "number" => 2 }),
        collection.data.insert({ "number" => 3 }),
        collection.data.insert({ "number" => nil })
      ]

      objects = collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, uuids, results)
    end
  end

  [
    [filter.by_property("ints").contains_any([1, 4]), [0, 3], nil],
    [filter.by_property("ints").contains_any([1.0, 4]), [0, 3], nil],
    [filter.by_property("ints").contains_any([10]), [], nil],
    [filter.by_property("int").contains_any([1]), [0, 1], nil],
    [filter.by_property("text").contains_any(["test"]), [0, 1], nil],
    [filter.by_property("text").contains_any(%w[real deal]), [1, 2, 3], nil],
    [filter.by_property("texts").contains_any(["test"]), [0, 1], nil],
    [filter.by_property("texts").contains_any(%w[real deal]), [1, 2, 3], nil],
    [filter.by_property("float").contains_any([2.0]), [], nil],
    [filter.by_property("float").contains_any([2]), [], nil],
    [filter.by_property("float").contains_any([8]), [3], nil],
    [filter.by_property("float").contains_any([8.0]), [3], nil],
    [filter.by_property("floats").contains_any([2.0]), [0, 1], nil],
    [filter.by_property("floats").contains_any([0.4, 0.7]), [0, 1, 3], nil],
    [filter.by_property("floats").contains_any([2]), [0, 1], nil],
    [filter.by_property("bools").contains_any([true, false]), [0, 1, 3], nil],
    [filter.by_property("bools").contains_any([false]), [0, 1], nil],
    [filter.by_property("bool").contains_any([true]), [0, 1, 3], nil],
    [filter.by_property("ints").contains_all([1, 4]), [0], nil],
    [filter.by_property("text").contains_all(%w[real test]), [1], nil],
    [filter.by_property("texts").contains_all(%w[real test]), [1], nil],
    [filter.by_property("floats").contains_all([0.7, 2]), [1], nil],
    [filter.by_property("bools").contains_all([true, false]), [0], nil],
    [filter.by_property("bool").contains_all([true, false]), [], nil],
    [filter.by_property("bool").contains_all([true]), [0, 1, 3], nil],
    [filter.by_property("dates").contains_any([now, much_later]), [0, 1, 3], nil],
    [filter.by_property("dates").contains_any([now]), [0, 1], nil],
    [filter.by_property("date").equal(now), [0], nil],
    [filter.by_property("date").greater_than(now), [1, 3], nil],
    [filter.by_property("uuids").contains_all([uuid2, uuid1]), [0, 3], nil],
    [filter.by_property("uuids").contains_any([uuid2, uuid1]), [0, 1, 3], nil],
    [filter.by_property("uuid").contains_any([uuid3]), [], nil],
    [filter.by_property("uuid").contains_any([uuid1]), [0], nil],
    [filter.by_property("_id").contains_any([uuid1, uuid3]), [0, 2], nil],
    [filter.by_property("_id").contains_none([uuid1, uuid2, uuid3, uuid4]), [], [1, 33, 0]]
  ].each_with_index do |(weaviate_filter, results, require_version), i|
    it "test_filters_contains[weaviate_filter#{i}-results#{i}-require_version#{i}]" do
      collection = collection_factory(
        vector_config: config::Configure::Vectors.self_provided,
        properties: [
          config::Property.new(name: "text", data_type: config::DataType::TEXT),
          config::Property.new(name: "texts", data_type: config::DataType::TEXT_ARRAY),
          config::Property.new(name: "int", data_type: config::DataType::INT),
          config::Property.new(name: "ints", data_type: config::DataType::INT_ARRAY),
          config::Property.new(name: "float", data_type: config::DataType::NUMBER),
          config::Property.new(name: "floats", data_type: config::DataType::NUMBER_ARRAY),
          config::Property.new(name: "bool", data_type: config::DataType::BOOL),
          config::Property.new(name: "bools", data_type: config::DataType::BOOL_ARRAY),
          config::Property.new(name: "dates", data_type: config::DataType::DATE_ARRAY),
          config::Property.new(name: "date", data_type: config::DataType::DATE),
          config::Property.new(name: "uuids", data_type: config::DataType::UUID_ARRAY),
          config::Property.new(name: "uuid", data_type: config::DataType::UUID)
        ]
      )

      if require_version && client_factory.connection.weaviate_version.is_lower_than(*require_version)
        skip("#{weaviate_filter.inspect} is not supported in v#{require_version.join(".")}")
      end

      # Ruby equivalent of pytest's recwarn: record all client warnings emitted from here on.
      _, warnings = Weaviate::Warnings.capture do
        uuids = [
          collection.data.insert(
            {
              "text" => "this is a test",
              "texts" => "this is a test".split,
              "int" => 1,
              "ints" => [1, 2, 4],
              "float" => 0.5,
              "floats" => [0.4, 0.9, 2],
              "bool" => true,
              "bools" => [true, false],
              "dates" => [now, later, much_later],
              "date" => now,
              "uuids" => [uuid1, uuid3, uuid2],
              "uuid" => uuid1
            },
            uuid: uuid1
          ),
          collection.data.insert(
            {
              "text" => "this is not a real test",
              "texts" => "this is not a real test".split,
              "int" => 1,
              "ints" => [5, 6, 9],
              "float" => 0.3,
              "floats" => [0.1, 0.7, 2],
              "bool" => true,
              "bools" => [false, false],
              "dates" => [now, now, much_later],
              "date" => later,
              "uuids" => [uuid2, uuid2],
              "uuid" => uuid2
            },
            uuid: uuid2
          ),
          collection.data.insert(
            {
              "text" => "real deal",
              "texts" => "real deal".split,
              "int" => 3,
              "ints" => [],
              "floats" => [],
              "bool" => false,
              "bools" => [],
              "dates" => [],
              "uuids" => []
            },
            uuid: uuid3
          ),
          collection.data.insert(
            {
              "text" => "not real deal",
              "texts" => "not real deal".split,
              "int" => 4,
              "ints" => [4],
              "float" => 8,
              "floats" => [0.7],
              "bool" => true,
              "bools" => [true],
              "dates" => [much_later],
              "date" => much_later,
              "uuids" => [uuid1, uuid2],
              "uuid" => uuid2
            },
            uuid: uuid4
          )
        ]

        objects = collection.query.fetch_objects(filters: weaviate_filter).objects
        expect_uuids(objects, uuids, results)
      end

      # Check for warnings to make sure booleans are handled as their correct type and are not sent as ints
      expect(warnings).to eq([])
    end
  end

  [
    [filter.by_ref("ref").by_property("int").greater_than(3), [1]],
    [filter.by_ref("ref").by_property("text", length: true).less_than(6), [0]],
    [filter.by_ref("ref").by_id.equal(uuid2), [1]],
    # second obj links to first one
    [filter.by_ref("ref2").by_ref("ref").by_property("text", length: true).less_than(6), [2]]
  ].each_with_index do |(weaviate_filter, results), i|
    it "test_ref_filters[weaviate_filter#{i}-results#{i}]" do
      to_collection = collection_factory(
        name: "Target",
        vectorizer_config: config::Configure::Vectorizer.none,
        properties: [
          config::Property.new(name: "int", data_type: config::DataType::INT),
          config::Property.new(name: "text", data_type: config::DataType::TEXT)
        ],
        inverted_index_config: config::Configure.inverted_index(index_property_length: true)
      )

      uuids_to = [
        to_collection.data.insert(properties: { "int" => 0, "text" => "first" }, uuid: uuid1),
        to_collection.data.insert(properties: { "int" => 15, "text" => "second" }, uuid: uuid2)
      ]
      from_collection = collection_factory(
        properties: [config::Property.new(name: "name", data_type: config::DataType::TEXT)],
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to_collection.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )
      from_collection.config.add_reference(
        config::ReferenceProperty.new(name: "ref2", target_collection: from_collection.name)
      )

      uuids_from = [
        from_collection.data.insert(properties: { "name" => "first" }, references: { "ref" => uuids_to[0] }),
        from_collection.data.insert(properties: { "name" => "second" }, references: { "ref" => uuids_to[1] })
      ]
      uuids_from.push(
        from_collection.data.insert(properties: { "name" => "third" }, references: { "ref2" => uuids_from[0] }),
        from_collection.data.insert(properties: { "name" => "fourth" }, references: { "ref2" => uuids_from[1] })
      )

      objects = from_collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, uuids_from, results)
    end
  end

  it "test_ref_filters_multi_target" do
    to_collection = collection_factory(
      name: "target",
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "int", data_type: config::DataType::INT)]
    )

    uuid_to = to_collection.data.insert(properties: { "int" => 0 })
    uuid_to2 = to_collection.data.insert(properties: { "int" => 5 })
    from_collection = collection_factory(
      name: "source",
      properties: [config::Property.new(name: "name", data_type: config::DataType::TEXT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    from_collection.config.add_reference(
      config::ReferenceProperty::MultiTarget.new(name: "ref",
                                                 target_collections: [to_collection.name, from_collection.name])
    )

    uuid_from_to_target1 = from_collection.data.insert(
      { "name" => "first" },
      references: { "ref" => data::ReferenceToMulti.new(uuids: uuid_to, target_collection: to_collection.name) }
    )
    uuid_from_to_target2 = from_collection.data.insert(
      { "name" => "second" },
      references: { "ref" => data::ReferenceToMulti.new(uuids: uuid_to2, target_collection: to_collection.name) }
    )
    from_collection.data.insert(
      { "name" => "third" },
      references: {
        "ref" => data::ReferenceToMulti.new(uuids: uuid_from_to_target1, target_collection: from_collection.name)
      }
    )
    from_collection.data.insert(
      { "name" => "fourth" },
      references: {
        "ref" => data::ReferenceToMulti.new(uuids: uuid_from_to_target2, target_collection: from_collection.name)
      }
    )

    objects = from_collection.query.fetch_objects(
      filters: filter.by_ref_multi_target("ref", target_collection: to_collection.name)
                     .by_property("int").greater_than(3)
    ).objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["name"]).to eq("second")

    objects = from_collection.query.fetch_objects(
      filters: filter.by_ref_multi_target("ref", target_collection: from_collection.name)
                     .by_property("name").equal("first")
    ).objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["name"]).to eq("third")
  end

  [
    filter.by_id.equal(uuid1),
    filter.by_id.contains_any([uuid1]),
    filter.by_id.not_equal(uuid2),
    filter.by_property("_id").equal(uuid1)
  ].each_with_index do |weav_filter, i|
    it "test_filter_id[weav_filter#{i}]" do
      collection = collection_factory(
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      collection.data.insert_many(
        [
          data::DataObject.new(properties: { "name" => "first" }, uuid: uuid1),
          data::DataObject.new(properties: { "name" => "second" }, uuid: uuid2)
        ]
      )

      objects = collection.query.fetch_objects(filters: weav_filter).objects

      expect(objects.length).to eq(1)
      expect(objects[0].uuid).to eq(uuid1)
    end
  end

  # Python's tuple inputs become frozen Arrays / Sets (any Enumerable is accepted).
  [
    [[], 0, Set.new],
    [[].freeze, 0, Set.new],
    [[uuid3], 1, Set[uuid3]],
    [[uuid1, uuid2], 2, Set[uuid1, uuid2]],
    [[uuid1, uuid3].freeze, 2, Set[uuid1, uuid3]],
    [[uuid1, uuid3, uuid3].freeze, 2, Set[uuid1, uuid3]]
  ].each_with_index do |(ids, expected_len, expected), i|
    it "test_filter_ids[ids#{i}-#{expected_len}-expected#{i}]" do
      collection = collection_factory(
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      collection.data.insert_many(
        [
          data::DataObject.new(properties: { "name" => "first" }, uuid: uuid1),
          data::DataObject.new(properties: { "name" => "second" }, uuid: uuid2),
          data::DataObject.new(properties: { "name" => "third" }, uuid: uuid3)
        ]
      )

      objects = collection.query.fetch_objects_by_ids(ids).objects

      expect(objects.length).to eq(expected_len)
      expect(objects.to_set(&:uuid)).to eq(expected)
    end
  end

  %w[_creationTimeUnix _lastUpdateTimeUnix].each do |path|
    it "test_filter_timestamp_direct_path[#{path}]" do
      collection = collection_factory(
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
        vectorizer_config: config::Configure::Vectorizer.none,
        inverted_index_config: config::Configure.inverted_index(index_timestamps: true)
      )

      obj1_uuid = collection.data.insert(properties: { "name" => "first" })
      sleep(0.01)
      obj2_uuid = collection.data.insert(properties: { "name" => "second" })

      obj2 = collection.query.fetch_object_by_id(obj2_uuid)
      expect(obj2).not_to be_nil
      expect(obj2.metadata).not_to be_nil
      expect(obj2.metadata.creation_time).not_to be_nil

      filters = filter.by_property(path).less_than(obj2.metadata.creation_time)
      objects = collection.query.fetch_objects(
        filters: filters, return_metadata: query::MetadataQuery.new(creation_time: true)
      ).objects

      expect(objects.length).to eq(1)
      expect(objects[0].uuid).to eq(obj1_uuid)
    end
  end

  it "test_time_update_and_creation_time" do
    collection = collection_factory(
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      vectorizer_config: config::Configure::Vectorizer.none,
      inverted_index_config: config::Configure.inverted_index(index_timestamps: true)
    )

    obj1_uuid = collection.data.insert(properties: { "name" => "first" })
    sleep(0.01)
    obj2_uuid = collection.data.insert(properties: { "name" => "second" })

    collection.data.update(uuid: obj1_uuid, properties: { "name" => "first updated" })

    obj1 = collection.query.fetch_object_by_id(obj1_uuid)
    expect(obj1).not_to be_nil
    expect(obj1.metadata).not_to be_nil
    expect(obj1.metadata.creation_time).not_to be_nil
    expect(obj1.metadata.last_update_time).not_to be_nil
    expect(obj1.metadata.creation_time).to be < obj1.metadata.last_update_time

    filter_creation = filter.by_update_time.less_than(obj1.metadata.creation_time)
    filter_update = filter.by_update_time.less_than(obj1.metadata.last_update_time)

    objects_creation = collection.query.fetch_objects(
      filters: filter_creation, return_metadata: query::MetadataQuery.new(creation_time: true)
    ).objects
    expect(objects_creation.length).to eq(0)

    objects_update = collection.query.fetch_objects(
      filters: filter_update, return_metadata: query::MetadataQuery.new(creation_time: true)
    ).objects
    expect(objects_update.length).to eq(1)
    expect(objects_update[0].uuid).to eq(obj2_uuid)
  end

  [
    [:equal, 2, [2]],
    [:not_equal, 1, [0, 2]],
    [:greater_than, 1, [2]],
    [:greater_or_equal, 1, [1, 2]],
    [:less_than, 1, [0]],
    [:less_or_equal, 1, [0, 1]]
  ].each_with_index do |(method, filter_value, results), i|
    it "test_time_filter[weav_filter#{i}-#{filter_value}-results#{i}]" do
      weav_filter = filter.by_creation_time.method(method)
      collection = collection_factory(
        vectorizer_config: config::Configure::Vectorizer.none,
        inverted_index_config: config::Configure.inverted_index(index_timestamps: true)
      )
      collection.data.insert(properties: {})
      sleep(0.01)
      collection.data.insert(properties: {})
      sleep(0.01)
      collection.data.insert(properties: {})

      all_objects = collection.query.fetch_objects(
        sort: query::Sort.by_creation_time, return_metadata: ["creation_time"]
      ).objects
      weaviate_filter = weav_filter.call(all_objects[filter_value].metadata.creation_time)
      objects = collection.query.fetch_objects(filters: weaviate_filter).objects
      expect_uuids(objects, all_objects.map(&:uuid), results)
    end
  end

  it "test_time_filter_contains" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      inverted_index_config: config::Configure.inverted_index(index_timestamps: true)
    )
    collection.data.insert(properties: {})
    sleep(0.01)
    uuid2_ = collection.data.insert(properties: {})
    sleep(0.01)
    uuid3_ = collection.data.insert(properties: {})

    obj2 = collection.query.fetch_object_by_id(uuid2_)
    obj3 = collection.query.fetch_object_by_id(uuid3_)

    objects = collection.query.fetch_objects(
      filters: filter.by_creation_time.contains_any([obj2.metadata.creation_time, obj3.metadata.creation_time])
    ).objects
    expect(objects.length).to eq(2)
    expect(objects.map(&:uuid)).to all(satisfy { |u| [uuid2_, uuid3_].include?(u) })
  end

  [
    [filter.by_ref_count("ref").not_equal(1), [0, 2]],
    [filter.by_ref_count("ref").less_than(2), [0, 1]],
    [filter.by_ref_count("ref").less_or_equal(1), [0, 1]],
    [filter.by_ref_count("ref").greater_than(0), [1, 2]],
    [filter.by_ref_count("ref").greater_or_equal(1), [1, 2]]
  ].each_with_index do |(weav_filter, results), i|
    it "test_ref_count_filter[weav_filter#{i}-results#{i}]" do
      collection = collection_factory
      collection.config.add_reference(config::ReferenceProperty.new(name: "ref", target_collection: collection.name))

      uuids = [
        collection.data.insert({}, uuid: uuid1),
        collection.data.insert({}, uuid: uuid2, references: { "ref" => uuid1 }),
        collection.data.insert({}, references: { "ref" => [uuid1, uuid2] }, uuid: uuid3)
      ]

      objects = collection.query.fetch_objects(filters: weav_filter).objects
      expect_uuids(objects, uuids, results)
    end
  end

  it "test_multi_target_ref_count_filter" do
    collection = collection_factory
    collection.config.add_reference(
      config::ReferenceProperty::MultiTarget.new(name: "ref", target_collections: [collection.name])
    )

    uuid1_ = collection.data.insert({})
    uuid2_ = collection.data.insert({})

    uuid3_ = collection.data.insert({}, references: { "ref" => [uuid1_, uuid2_] })

    objects = collection.query.fetch_objects(
      filters: filter.by_ref_count("ref").greater_than(0),
      return_references: query::QueryReference.new(link_on: "ref")
    ).objects
    expect(objects.length).to eq(1)
    expect(objects[0].uuid).to eq(uuid3_)
  end

  it "test_nested_ref_count_filter" do
    one = collection_factory(name: "one")
    two = collection_factory(
      name: "two", references: [config::ReferenceProperty.new(name: "ref2", target_collection: one.name)]
    )
    one.config.add_reference(config::ReferenceProperty.new(name: "ref1", target_collection: one.name))

    uuid11 = one.data.insert({})
    uuid12 = one.data.insert({}, references: { "ref1" => uuid11 })
    uuid13 = one.data.insert({}, references: { "ref1" => [uuid11, uuid12] })
    two.data.insert({})
    uuid21 = two.data.insert({}, references: { "ref2" => uuid12 })
    two.data.insert({}, references: { "ref2" => uuid13 })

    objects = two.query.fetch_objects(
      filters: filter.by_ref("ref2").by_ref_count("ref1").equal(1),
      return_references: query::QueryReference.new(link_on: "ref2")
    ).objects
    expect(objects.length).to eq(1)
    expect(objects[0].uuid).to eq(uuid21)
  end

  it "test_filter_by_ref_and_multi_ref" do
    one = collection_factory(name: "one")
    two = collection_factory(
      name: "two", references: [config::ReferenceProperty.new(name: "ref2", target_collection: one.name)]
    )
    one.config.add_reference(
      config::ReferenceProperty::MultiTarget.new(name: "ref1", target_collections: [one.name, two.name])
    )
    uuid11 = one.data.insert({})
    uuid12 = one.data.insert(
      {}, references: { "ref1" => data::ReferenceToMulti.new(uuids: uuid11, target_collection: one.name) }
    )
    uuid13 = one.data.insert(
      {},
      references: { "ref1" => data::ReferenceToMulti.new(uuids: [uuid11, uuid12], target_collection: one.name) }
    )

    two.data.insert({}, references: { "ref2" => uuid11 })
    two.data.insert({}, references: { "ref2" => uuid12 })
    uuid23 = two.data.insert({}, references: { "ref2" => uuid13 })

    objects = two.query.fetch_objects(
      filters: filter.by_ref("ref2")
                     .by_ref_multi_target("ref1", target_collection: one.name)
                     .by_ref_count("ref1")
                     .equal(1)
    ).objects

    expect(objects[0].uuid).to eq(uuid23)
  end
end
