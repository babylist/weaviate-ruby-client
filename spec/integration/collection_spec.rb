# frozen_string_literal: true

require "securerandom"

# Port of weaviate-python-client/integration/test_collection.py
RSpec.describe "collection", :integration do
  config = Weaviate::Classes::Config
  configure = config::Configure
  data_type = config::DataType
  property = config::Property
  reference_property = config::ReferenceProperty
  data_object = Weaviate::Classes::Data::DataObject
  reference_to_multi = Weaviate::Classes::Data::ReferenceToMulti
  phone_number = Weaviate::Classes::Data::PhoneNumber
  q = Weaviate::Classes::Query
  ex = Weaviate::Exceptions

  uuid1 = "806827e0-2b31-43ca-9269-24fa95a221f9"
  uuid2 = "8ad0d33c-8db1-4437-87f3-72161ca2a51a"
  uuid3 = "83d99755-9deb-4b16-8431-d1dff4ab0a75"

  date1 = Time.utc(2012, 2, 9)
  date2 = Time.utc(2013, 2, 10)
  date3 = Time.utc(2019, 6, 10)

  logo = IntegrationCollectionHelpers::WEAVIATE_LOGO_OLD_ENCODED

  def version_lower_than?(collection, major, minor, patch)
    collection.instance_variable_get(:@connection).weaviate_version.is_lower_than(major, minor, patch)
  end

  def name_props(**kw)
    [Weaviate::Classes::Config::Property.new(name: "Name", data_type: Weaviate::Classes::Config::DataType::TEXT, **kw)]
  end

  def self_provided = Weaviate::Classes::Config::Configure::Vectors.self_provided

  def contextionary
    Weaviate::Classes::Config::Configure::Vectors.text2vec_contextionary(vectorize_collection_name: false)
  end

  it "test_insert_with_typed_dict_generic" do
    # Python reads the collection through a TypedDict generic; Ruby has no typed data models, so plain hashes.
    dummy = collection_factory(properties: name_props, vector_config: self_provided)
    collection = collection_factory_get(dummy.name)
    uuid = collection.data.insert(properties: { "name" => "some name" })
    objects = collection.query.fetch_objects
    expect(objects.objects.length).to eq(1)
    name = collection.query.fetch_object_by_id(uuid).properties["name"]
    expect(name).to eq("some name")
  end

  it "test_insert_with_dict_generic" do
    dummy = collection_factory(properties: name_props, vector_config: self_provided)
    collection = collection_factory_get(dummy.name)
    uuid = collection.data.insert(properties: { "name" => "some name" })
    objects = collection.query.fetch_objects
    expect(objects.objects.length).to eq(1)
    name = collection.query.fetch_object_by_id(uuid).properties["name"]
    expect(name).to eq("some name")
  end

  it "test_insert_with_no_generic" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)
    uuid = collection.data.insert(properties: { "name" => "some name" })
    objects = collection.query.fetch_objects
    expect(objects.objects.length).to eq(1)
    prop = collection.query.fetch_object_by_id(uuid).properties["name"]
    expect(prop).to eq("some name")
  end

  it "test_insert_with_consistency_level" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)
                 .with_consistency_level(config::ConsistencyLevel::ALL)
    uuid = collection.data.insert(properties: { "name" => "some name" })
    objects = collection.query.fetch_objects
    expect(objects.objects.length).to eq(1)
    prop = collection.query.fetch_object_by_id(uuid).properties["name"]
    expect(prop).to eq("some name")
  end

  it "test_insert_bad_input" do
    collection = collection_factory
    bad_input = Class.new do
      def initialize
        @name = "test"
      end
    end

    expect { collection.data.insert({ "name" => bad_input }) }.to raise_error(ex::WeaviateInvalidInputError)
  end

  it "test_delete_by_id" do
    collection = collection_factory(vector_config: self_provided)

    uuid = collection.data.insert(properties: {})
    expect(collection.query.fetch_object_by_id(uuid)).not_to be_nil
    expect(collection.data.delete_by_id(uuid)).to be_truthy
    expect(collection.query.fetch_object_by_id(uuid)).to be_nil
  end

  it "test_delete_by_id_consistency_level" do
    collection = collection_factory(vector_config: self_provided).with_consistency_level(config::ConsistencyLevel::ALL)

    uuid = collection.data.insert(properties: {})
    expect(collection.query.fetch_object_by_id(uuid)).not_to be_nil
    expect(collection.data.delete_by_id(uuid)).to be_truthy
    expect(collection.query.fetch_object_by_id(uuid)).to be_nil
  end

  insert_many_params = [
    [-> {
      [data_object.new(properties: { "name" => "some name" }, vector: [1, 2, 3]),
       data_object.new(properties: { "name" => "some other name" }, uuid: SecureRandom.uuid)]
    }, false],
    [-> { [{ "name" => "some name" }, data_object.new(properties: { "name" => "some other name" })] }, false],
    [-> { [{ "name" => "some name" }, { "name" => "some other name" }] }, false],
    [-> {
      [data_object.new(properties: {}),
       data_object.new(properties: {}, vector: [1, 2, 3]),
       data_object.new(properties: {}, uuid: SecureRandom.uuid),
       data_object.new(properties: {}, vector: [1, 2, 3], uuid: SecureRandom.uuid)]
    }, false],
    [-> { [{ "name" => "some name", "vector" => [1, 2, 3] }] }, true],
    [-> { [{ "name" => "some name", "vector" => [1, 2, 3] }, data_object.new(properties: { "name" => "some other name" })] },
     true],
    [-> {
      [{ "name" => "some name", "vector" => [1, 2, 3] },
       data_object.new(properties: { "name" => "some other name" }, uuid: SecureRandom.uuid, vector: [1, 2, 3])]
    }, true],
    [-> { [{ "name" => "some name", "id" => SecureRandom.uuid }] }, true]
  ]
  insert_many_params.each_with_index do |(objects_maker, should_error), param_idx|
    it "test_insert_many[objects#{param_idx}-#{should_error}]" do
      objects = objects_maker.call
      collection = collection_factory(properties: name_props, vector_config: self_provided)
      if should_error
        expect { collection.data.insert_many(objects) }.to raise_error(ex::WeaviateInsertInvalidPropertyError) { |e|
          expect(e.message).to eq(
            "It is forbidden to insert `id` or `vector` inside properties: #{objects[0]}. Only properties defined in " \
            "your collection's config can be inserted as properties of the object, `id` is totally forbidden as it " \
            "is reserved and `vector` is forbidden at this level. You should use the `DataObject` class if you wish " \
            "to insert an object with a custom `vector` whilst inserting its properties."
          )
        }
      else
        ret = collection.data.insert_many(objects)
        ret.uuids.each do |idx, uuid_|
          obj1 = collection.query.fetch_object_by_id(uuid_)
          inserted = objects[idx]
          if inserted.is_a?(data_object) && inserted.properties.empty?
            if obj1.properties.key?("name") # change this when server version bumps to 1.24.0
              expect(obj1.properties["name"]).to be_nil
            else
              expect(obj1.properties).to eq({})
            end
          elsif inserted.is_a?(data_object) && !inserted.properties.nil?
            expect(obj1.properties["name"]).to eq(inserted.properties["name"])
          else
            expect(inserted).not_to be_a(data_object)
            expect(obj1.properties["name"]).to eq(inserted["name"])
          end
        end
      end
    end
  end

  it "test_insert_many_all_error" do
    collection = collection_factory(
      properties: name_props, vector_config: self_provided, multi_tenancy_config: configure.multi_tenancy(enabled: true)
    )
    expect do
      collection.data.insert_many([{ "name" => "steve" }, { "name" => "bob" }, { "name" => "joe" }])
    end.to raise_error(ex::WeaviateInsertManyAllFailedError) { |e|
      expect(e.message).to eq(
        "Every object failed during insertion. Here is the set of all errors: class #{collection.name} has " \
        "multi-tenancy enabled, but request was without tenant"
      )
    }
  end

  it "test_insert_many_with_typed_dict" do
    # Python inserts TypedDict instances; plain hashes are the Ruby equivalent.
    dummy = collection_factory(properties: name_props, vector_config: self_provided)
    collection = collection_factory_get(dummy.name)
    ret = collection.data.insert_many(
      [
        data_object.new(properties: { "name" => "some name" }, vector: [1, 2, 3]),
        data_object.new(properties: { "name" => "some other name" }, uuid: SecureRandom.uuid)
      ]
    )
    obj1 = collection.query.fetch_object_by_id(ret.uuids[0])
    obj2 = collection.query.fetch_object_by_id(ret.uuids[1])
    expect(obj1.properties["name"]).to eq("some name")
    expect(obj2.properties["name"]).to eq("some other name")
  end

  it "test_insert_many_with_refs" do
    ref_collection = collection_factory(name: "target", vector_config: self_provided)
    uuid_to1 = ref_collection.data.insert(properties: {})
    uuid_to2 = ref_collection.data.insert(properties: {})

    collection = collection_factory(
      name: "source",
      properties: name_props,
      references: [reference_property.new(name: "ref_single", target_collection: ref_collection.name)],
      vector_config: self_provided
    )
    collection.config.add_reference(
      reference_property::MultiTarget.new(name: "ref_many", target_collections: [ref_collection.name, collection.name])
    )
    uuid_from = collection.data.insert(properties: { "name" => "first" })

    ret = collection.data.insert_many(
      [
        data_object.new(
          properties: { "name" => "some name" },
          references: {
            "ref_single" => [uuid_to1, uuid_to2],
            "ref_many" => reference_to_multi.new(uuids: [uuid_from], target_collection: collection.name)
          },
          vector: [1, 2, 3]
        ),
        data_object.new(
          properties: { "name" => "some other name" },
          references: {
            "ref_single" => uuid_to2,
            "ref_many" => reference_to_multi.new(uuids: uuid_to1, target_collection: ref_collection.name)
          },
          uuid: SecureRandom.uuid
        )
      ]
    )
    obj1 = collection.query.fetch_object_by_id(
      ret.uuids[0],
      return_properties: ["name"],
      return_references: [
        q::QueryReference.new(link_on: "ref_single"),
        q::QueryReference::MultiTarget.new(link_on: "ref_many", target_collection: collection.name)
      ]
    )
    expect(obj1).not_to be_nil
    expect(obj1.properties["name"]).to eq("some name")
    expect(obj1.references["ref_many"]).to be_a(Weaviate::Outputs::Query::CrossReference)
    expect(obj1.references["ref_single"]).to be_a(Weaviate::Outputs::Query::CrossReference)

    obj1 = collection.query.fetch_object_by_id(
      ret.uuids[1],
      return_properties: ["name"],
      return_references: [
        q::QueryReference.new(link_on: "ref_single"),
        q::QueryReference::MultiTarget.new(link_on: "ref_many", target_collection: ref_collection.name)
      ]
    )
    expect(obj1).not_to be_nil
    expect(obj1.properties["name"]).to eq("some other name")
    expect(obj1.references["ref_many"]).to be_a(Weaviate::Outputs::Query::CrossReference)
    expect(obj1.references["ref_single"]).to be_a(Weaviate::Outputs::Query::CrossReference)
  end

  it "test_insert_many_error" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)
    ret = collection.data.insert_many(
      [
        data_object.new(properties: { "wrong_name" => "some name" }, vector: [1, 2, 3]),
        data_object.new(properties: { "name" => "some other name" }, uuid: SecureRandom.uuid),
        data_object.new(properties: { "other_thing" => "is_wrong" }, vector: [1, 2, 3])
      ]
    )
    expect(ret.has_errors).to be(true)

    obj = collection.query.fetch_object_by_id(ret.uuids[1])
    expect(obj.properties["name"]).to eq("some other name")

    expect(ret.errors.length).to eq(2)
    expect(ret.errors).to include(0, 2)

    expect(ret.all_responses[0]).to be_a(Weaviate::Outputs::Batch::ErrorObject)
    expect(ret.all_responses[2]).to be_a(Weaviate::Outputs::Batch::ErrorObject)
    # UUIDs are Strings in Ruby
    expect(ret.all_responses[1]).to eq(Weaviate::Util.get_valid_uuid(ret.all_responses[1]))
  end

  it "test_replace" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)
    uuid = collection.data.insert(properties: { "name" => "some name" })
    collection.data.replace(properties: { "name" => "other name" }, uuid: uuid)
    expect(collection.query.fetch_object_by_id(uuid).properties["name"]).to eq("other name")
  end

  { "to_uuids0" => uuid3, "to_uuids1" => [uuid3] }.each do |param_id, to_uuids|
    it "test_replace_with_refs[#{param_id}]" do
      ref_collection = collection_factory(name: "target", vector_config: self_provided)
      ref_collection.data.insert(properties: {}, uuid: uuid1)
      ref_collection.data.insert(properties: {}, uuid: uuid2)
      ref_collection.data.insert(properties: {}, uuid: uuid3)

      collection = collection_factory(
        name: "source",
        properties: name_props,
        references: [reference_property.new(name: "ref", target_collection: ref_collection.name)],
        vector_config: self_provided
      )
      uuid = collection.data.insert(properties: { "name" => "some name" }, references: { "ref" => [uuid1, uuid2] })

      collection.data.replace(properties: { "name" => "other name" }, uuid: uuid, references: { "ref" => to_uuids })
      obj = collection.query.fetch_object_by_id(
        uuid, return_properties: ["name"], return_references: [q::QueryReference.new(link_on: "ref")]
      )
      expect(obj.references["ref"].objects.length).to eq(1)
      expect(obj.references["ref"].objects[0].uuid).to eq(uuid3)
    end
  end

  it "test_replace_overwrites_vector" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)
    uuid = collection.data.insert(properties: { "name" => "some name" }, vector: [1, 2, 3])
    obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
    expect(obj.properties["name"]).to eq("some name")
    expect(obj.vector["default"]).to eq([1, 2, 3])

    collection.data.replace(properties: { "name" => "other name" }, uuid: uuid)
    obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
    expect(obj.properties["name"]).to eq("other name")
    if version_lower_than?(collection, 1, 27, 0)
      expect(obj.vector["default"].length).to eq(0)
    else
      expect(obj.vector).not_to include("default")
    end

    collection.data.replace(properties: { "name" => "real name" }, uuid: uuid, vector: [2, 3, 4])
    obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
    expect(obj.properties["name"]).to eq("real name")
    expect(obj.vector["default"]).to eq([2, 3, 4])
  end

  { "to_uuids0" => uuid3, "to_uuids1" => [uuid3] }.each do |param_id, to_uuids|
    it "test_update_with_refs[#{param_id}]" do
      ref_collection = collection_factory(name: "target", vector_config: self_provided)
      ref_collection.data.insert(properties: {}, uuid: uuid1)
      ref_collection.data.insert(properties: {}, uuid: uuid2)
      ref_collection.data.insert(properties: {}, uuid: uuid3)

      collection = collection_factory(
        name: "source",
        properties: name_props,
        references: [reference_property.new(name: "ref", target_collection: ref_collection.name)],
        vector_config: self_provided
      )
      uuid = collection.data.insert(properties: { "name" => "some name" }, references: { "ref" => [uuid1, uuid2] })

      collection.data.update(uuid: uuid, references: { "ref" => to_uuids })
      obj = collection.query.fetch_object_by_id(
        uuid, return_properties: ["name"], return_references: [q::QueryReference.new(link_on: "ref")]
      )
      expect(obj.references["ref"].objects.length).to eq(3)
      expect(obj.references["ref"].objects[2].uuid).to eq(uuid3)
    end
  end

  [
    [data_type::TEXT, "1"],
    [data_type::INT, 1],
    [data_type::NUMBER, 0.5],
    [data_type::TEXT_ARRAY, %w[1 2]],
    [data_type::INT_ARRAY, [1, 2]],
    [data_type::NUMBER_ARRAY, [1.0, 2.1]],
    [data_type::NUMBER_ARRAY, []]
  ].each do |dt, value|
    it "test_types[#{dt}-#{value.inspect}]" do
      name = "name"
      collection = collection_factory(properties: [property.new(name: name, data_type: dt)], vector_config: self_provided)
      uuid_object = collection.data.insert(properties: { name => value })

      object_get = collection.query.fetch_object_by_id(uuid_object)
      expect(object_get).not_to be_nil
      expect(object_get.properties[name]).to eq(value)

      batch_return = collection.data.insert_many([{ name => value }])
      expect(batch_return.has_errors).to be(false)

      object_get_from_batch = collection.query.fetch_object_by_id(batch_return.uuids[0])
      expect(object_get_from_batch).not_to be_nil
      expect(object_get_from_batch.properties[name]).to eq(value)
    end
  end

  it "test_bm25" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)

    res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
    expect(res.has_errors).to be(false)
    expect(collection.query.bm25("test").objects.length).to eq(2)
  end

  it "test_bm25_group_by" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)

    res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
    expect(res.has_errors).to be(false)
    objs = collection.query.bm25(
      "test", group_by: q::GroupBy.new(prop: "name", objects_per_group: 1, number_of_groups: 2)
    ).objects
    expect(objs.length).to eq(1)
    expect(objs[0].belongs_to_group).to eq("test")
  end

  [1, 2].each do |limit|
    it "test_bm25_limit[#{limit}]" do
      collection = collection_factory(properties: name_props(tokenization: config::Tokenization::WORD),
                                      vector_config: self_provided)

      res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
      expect(res.has_errors).to be(false)
      expect(collection.query.bm25("test", limit: limit).objects.length).to eq(limit)
    end
  end

  [[0, 2], [1, 1], [2, 0]].each do |offset, expected|
    it "test_bm25_offset[#{offset}-#{expected}]" do
      collection = collection_factory(properties: name_props(tokenization: config::Tokenization::WORD),
                                      vector_config: self_provided)

      res = collection.data.insert_many([{ "Name" => "test" }, { "Name" => "another" }, { "Name" => "test" }])
      expect(res.has_errors).to be(false)

      expect(collection.query.bm25("test", offset: offset).objects.length).to eq(expected)
    end
  end

  [0, 1, 5].each do |offset|
    it "test_fetch_objects_offset[#{offset}]" do
      collection = collection_factory(properties: name_props, vector_config: self_provided)

      nr_objects = 5
      nr_objects.times { |i| collection.data.insert({ "Name" => i.to_s }) }

      objects = collection.query.fetch_objects(offset: offset).objects
      expect(objects.length).to eq(nr_objects - offset)
    end
  end

  [1, 5].each do |limit|
    it "test_fetch_objects_limit[#{limit}]" do
      collection = collection_factory(properties: name_props, vector_config: self_provided)
      5.times { |i| collection.data.insert({ "Name" => i.to_s }) }

      expect(collection.query.fetch_objects(limit: limit).objects.length).to eq(limit)
    end
  end

  it "test_search_after" do
    collection = collection_factory(properties: name_props, vector_config: self_provided)

    nr_objects = 10
    nr_objects.times { |i| collection.data.insert({ "Name" => i.to_s }) }

    objects = collection.query.fetch_objects.objects
    objects.each_with_index do |obj, i|
      objects_after = collection.query.fetch_objects(after: obj.uuid).objects
      expect(objects_after.length).to eq(nr_objects - 1 - i)
    end
  end

  it "test_auto_limit" do
    collection = collection_factory(properties: name_props, vector_config: self_provided,
                                    inverted_index_config: configure.inverted_index)
    4.times { collection.data.insert({ "Name" => "rain rain" }) }
    4.times { collection.data.insert({ "Name" => "rain" }) }
    4.times { collection.data.insert({ "Name" => "" }) }

    # match all objects with rain
    objects = collection.query.bm25("rain", auto_limit: 0).objects
    expect(objects.length).to eq(2 * 4)
    objects = collection.query.hybrid(
      "rain", auto_limit: 0, alpha: 0, fusion_type: q::HybridFusion::RELATIVE_SCORE
    ).objects
    expect(objects.length).to eq(2 * 4)

    # match only objects with two rains
    objects = collection.query.bm25("rain", auto_limit: 1).objects
    expect(objects.length).to eq(1 * 4)
    objects = collection.query.hybrid(
      "rain", auto_limit: 1, alpha: 0, fusion_type: q::HybridFusion::RELATIVE_SCORE
    ).objects
    expect(objects.length).to eq(1 * 4)
  end

  it "test_query_properties" do
    collection = collection_factory(
      properties: [property.new(name: "Name", data_type: data_type::TEXT), property.new(name: "Age", data_type: data_type::INT)],
      vector_config: self_provided
    )
    collection.data.insert({ "Name" => "rain", "Age" => 1 })
    collection.data.insert({ "Name" => "sun", "Age" => 2 })
    collection.data.insert({ "Name" => "cloud", "Age" => 3 })
    collection.data.insert({ "Name" => "snow", "Age" => 4 })
    collection.data.insert({ "Name" => "hail", "Age" => 5 })

    objects = collection.query.bm25("rain", query_properties: ["name"]).objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["age"]).to eq(1)

    objects = collection.query.bm25("sleet", query_properties: ["name"]).objects
    expect(objects.length).to eq(0)

    objects = collection.query.hybrid("cloud", query_properties: ["name"], alpha: 0).objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["age"]).to eq(3)

    objects = collection.query.hybrid("sleet", query_properties: ["name"], alpha: 0).objects
    expect(objects.length).to eq(0)
  end

  it "test_near_object" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(properties: name_props, vector_config: contextionary)
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    full_objects = collection.query.near_object(
      uuid_banana, return_metadata: q::MetadataQuery.new(distance: true, certainty: true)
    ).objects
    expect(full_objects.length).to eq(4)

    objects_distance = collection.query.near_object(uuid_banana, distance: full_objects[2].metadata.distance).objects
    expect(objects_distance.length).to eq(3)

    objects_certainty = collection.query.near_object(uuid_banana, certainty: full_objects[2].metadata.certainty).objects
    expect(objects_certainty.length).to eq(3)
  end

  it "test_near_object_limit" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(properties: name_props, vector_config: contextionary)
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    uuid_fruit = collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    banana = collection.query.fetch_object_by_id(uuid_banana)

    objs = collection.query.near_object(banana.uuid, limit: 2).objects
    expect(objs.length).to eq(2)
    expect(objs[0].uuid).to eq(uuid_banana)
    expect(objs[1].uuid).to eq(uuid_fruit)
  end

  it "test_near_object_offset" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(properties: name_props, vector_config: contextionary)
    uuid_banana = collection.data.insert({ "Name" => "Banana" })
    uuid_fruit = collection.data.insert({ "Name" => "Fruit" })
    collection.data.insert({ "Name" => "car" })
    collection.data.insert({ "Name" => "Mountain" })

    banana = collection.query.fetch_object_by_id(uuid_banana)

    objs = collection.query.near_object(banana.uuid, offset: 1).objects
    expect(objs.length).to eq(3)
    expect(objs[0].uuid).to eq(uuid_fruit)
  end

  it "test_near_object_group_by_argument" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(
      properties: [property.new(name: "Name", data_type: data_type::TEXT), property.new(name: "Count", data_type: data_type::INT)],
      vector_config: contextionary
    )
    uuid_banana1 = collection.data.insert({ "Name" => "Banana", "Count" => 51 })
    collection.data.insert({ "Name" => "Banana", "Count" => 72 })
    collection.data.insert({ "Name" => "car", "Count" => 12 })
    collection.data.insert({ "Name" => "Mountain", "Count" => 1 })

    ret = collection.query.near_object(
      uuid_banana1,
      group_by: q::GroupBy.new(prop: "name", number_of_groups: 4, objects_per_group: 10),
      return_metadata: q::MetadataQuery.new(distance: true, certainty: true)
    )

    expect(ret.objects.length).to eq(4)
    expect(ret.objects[0].belongs_to_group).to eq("Banana")
    expect(ret.objects[1].belongs_to_group).to eq("Banana")
    expect(ret.objects[2].belongs_to_group).to eq("Mountain")
    expect(ret.objects[3].belongs_to_group).to eq("car")
  end

  it "test_multi_searches" do
    collection = collection_factory(properties: [property.new(name: "name", data_type: data_type::TEXT)],
                                    vector_config: self_provided)

    collection.data.insert(properties: { "name" => "word" })
    collection.data.insert(properties: { "name" => "other" })

    objects = collection.query.bm25(
      "word", return_properties: ["name"], return_metadata: q::MetadataQuery.new(last_update_time: true)
    ).objects
    expect(objects[0].properties).to include("name")
    expect(objects[0].metadata.last_update_time).not_to be_nil

    objects = collection.query.bm25("other").objects
    expect(objects[0].properties).to include("name")
    expect(objects[0].uuid).not_to be_nil
    expect(objects[0].metadata.is_empty).to be(true)

    objects = collection.query.bm25("other", return_properties: []).objects
    expect(objects[0].properties).not_to include("name")
    expect(objects[0].uuid).not_to be_nil
    expect(objects[0].metadata.is_empty).to be(true)
  end

  it "test_fetch_objects_with_limit" do
    collection = collection_factory(vector_config: self_provided,
                                    properties: [property.new(name: "name", data_type: data_type::TEXT)])

    10.times { |i| collection.data.insert({ "name" => i.to_s }) }

    objects = collection.query.fetch_objects(limit: 5).objects
    expect(objects.length).to eq(5)
  end

  it "test_add_property" do
    collection = collection_factory(vector_config: self_provided,
                                    properties: [property.new(name: "name", data_type: data_type::TEXT)])
    first_uuid = collection.data.insert({ "name" => "first" })
    collection.config.add_property(property.new(name: "number", data_type: data_type::INT))
    second_uuid = collection.data.insert({ "name" => "second", "number" => 5 })
    obj1 = collection.query.fetch_object_by_id(first_uuid)
    obj2 = collection.query.fetch_object_by_id(second_uuid)
    expect(obj1.properties).to include("name")
    expect(obj2.properties).to include("name")
    expect(obj2.properties).to include("number")
  end

  it "test_add_property_with_vectorizer" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(vector_config: contextionary,
                                    properties: [property.new(name: "name", data_type: data_type::TEXT)])
    collection.config.add_property(
      property.new(name: "newPropertyAllTrue", data_type: data_type::TEXT, skip_vectorization: true,
                   vectorize_property_name: true)
    )
    collection.config.add_property(
      property.new(name: "newPropertyAllFalse", data_type: data_type::TEXT, skip_vectorization: false,
                   vectorize_property_name: false)
    )
    new_property_true = collection.config.get.to_dict["properties"].find { |item| item["name"] == "newPropertyAllTrue" }
    mconfig = new_property_true["moduleConfig"]["text2vec-contextionary"]
    expect(mconfig["skip"]).to be(true)
    expect(mconfig["vectorizePropertyName"]).to be(true)

    new_property_false = collection.config.get.to_dict["properties"].find { |item| item["name"] == "newPropertyAllFalse" }
    mconfig = new_property_false["moduleConfig"]["text2vec-contextionary"]
    expect(mconfig["skip"]).to be(false)
    expect(mconfig["vectorizePropertyName"]).to be(false)
  end

  it "test_add_reference" do
    collection = collection_factory(vector_config: self_provided,
                                    properties: [property.new(name: "name", data_type: data_type::TEXT)])
    first_uuid = collection.data.insert({ "name" => "first" })
    collection.config.add_reference(reference_property.new(name: "self", target_collection: collection.name))
    second_uuid = collection.data.insert({ "name" => "second" }, references: { "self" => first_uuid })
    obj1 = collection.query.fetch_object_by_id(
      first_uuid, return_properties: ["name"], return_references: q::QueryReference.new(link_on: "self")
    )
    obj2 = collection.query.fetch_object_by_id(
      second_uuid, return_properties: ["name"], return_references: q::QueryReference.new(link_on: "self")
    )
    expect(obj1.properties).to include("name")
    expect(obj1.references).to eq({})
    expect(obj2.properties).to include("name")
    expect(obj2.references).to include("self")
  end

  it "test_collection_config_get" do
    collection = collection_factory(
      vector_config: self_provided,
      properties: [property.new(name: "name", data_type: data_type::TEXT), property.new(name: "age", data_type: data_type::INT)]
    )
    cfg = collection.config.get
    expect(cfg.name).to eq(collection.name)
    expect(cfg.properties.length).to eq(2)
    expect(cfg.properties[0].name).to eq("name")
    expect(cfg.properties[0].data_type).to eq(data_type::TEXT)
    expect(cfg.properties[1].name).to eq("age")
    expect(cfg.properties[1].data_type).to eq(data_type::INT)
    expect(cfg.vectorizer).to be_nil
    expect(cfg.vector_config).not_to be_nil
    expect(cfg.vector_config["default"].vectorizer.vectorizer).to eq(config::Vectorizers::NONE)
  end

  combo_return_properties = { "None" => nil, "[]" => [], "['name']" => ["name"], "False" => false, "True" => true }
  combo_return_metadata = {
    "None" => -> {},
    "[]" => -> { [] },
    "MetadataQuery()" => -> { q::MetadataQuery.new },
    "list" => -> { %w[creation_time last_update_time distance certainty score explain_score is_consistent] },
    "full" => -> { q::MetadataQuery.full }
  }
  combo_return_references = {
    "None" => -> {},
    "[]" => -> { [] },
    "[QueryReference(friend)]" => -> { [q::QueryReference.new(link_on: "friend")] }
  }
  [false, true].each do |include_vector|
    combo_return_references.each do |rr_id, return_references_maker|
      combo_return_metadata.each do |rm_id, return_metadata_maker|
        combo_return_properties.each do |rp_id, return_properties|
          it "test_return_properties_metadata_references_combos[#{include_vector}-#{rr_id}-#{rm_id}-#{rp_id}]" do
            return_metadata = return_metadata_maker.call
            return_references = return_references_maker.call
            collection = collection_factory(
              vector_config: self_provided,
              properties: [property.new(name: "name", data_type: data_type::TEXT),
                           property.new(name: "age", data_type: data_type::INT)]
            )
            collection.config.add_reference(
              reference_property.new(name: "friend",
                                     target_collection: IntegrationContext.sanitize_collection_name(collection.name))
            )

            collection.data.insert(uuid: uuid1, properties: { "name" => "Graham", "age" => 42 }, vector: [1, 2, 3, 4])
            collection.data.insert(uuid: uuid2, properties: { "name" => "John", "age" => 43 }, vector: [1, 2, 3, 4],
                                   references: { "friend" => uuid1 })

            objects = collection.query.fetch_objects(
              include_vector: include_vector,
              return_properties: return_properties,
              return_metadata: return_metadata,
              return_references: return_references
            ).objects

            obj = objects.find { |o| o.uuid == uuid2 }

            expect(obj.uuid).not_to be_nil

            if return_properties.nil? || return_properties == true
              expect(obj.properties).to include("name", "age")
              expect(obj.properties["name"]).to eq("John")
              expect(obj.properties["age"]).to eq(43)
            elsif return_properties == false || return_properties.empty?
              expect(obj.properties).not_to include("name")
              expect(obj.properties).not_to include("age")
            else
              expect(obj.properties).to include("name")
              expect(obj.properties).not_to include("age")
              expect(obj.properties["name"]).to eq("John")
            end

            if return_metadata.nil? || return_metadata == q::MetadataQuery.new ||
               (return_metadata.is_a?(Array) && return_metadata.empty?)
              expect(obj.metadata.is_empty).to be(true)
            else
              expect(obj.metadata.last_update_time).not_to be_nil
              expect(obj.metadata.creation_time).not_to be_nil
              expect(obj.metadata.explain_score).not_to be_nil
            end

            if include_vector
              expect(obj.vector["default"]).to eq([1, 2, 3, 4])
            else
              expect(obj.vector).not_to include("default")
            end

            if return_references.nil? || return_references.empty?
              expect(obj.references).to be_nil
            else
              expect(obj.references).not_to be_nil
              expect(obj.references["friend"].objects[0].uuid).to eq(uuid1)
              expect(obj.references["friend"].objects[0].properties["name"]).to eq("Graham")
              expect(obj.references["friend"].objects[0].properties["age"]).to eq(42)
            end
          end
        end
      end
    end
  end

  [[0, 0, 1], [1, 20, -1], [2, 0, 1], [3, 40, -1]].each do |hours, minutes, sign|
    it "test_insert_date_property[#{hours}-#{minutes}-#{sign}]" do
      collection = collection_factory(vector_config: self_provided,
                                      properties: [property.new(name: "date", data_type: data_type::DATE)])

      offset = sign * ((hours * 3600) + (minutes * 60))
      # Python datetimes have microsecond precision; truncate Ruby's nanosecond clock to match.
      t = Time.now
      now = Time.at(t.to_i, t.usec, :usec, in: offset)
      uuid = collection.data.insert(properties: { "date" => now })

      obj = collection.query.fetch_object_by_id(uuid)

      expect(obj.properties["date"]).to eq(now)
    end
  end

  it "test_exist" do
    collection = collection_factory(vector_config: self_provided)

    uuid1_ = collection.data.insert({})

    expect(collection.data.exists(uuid1_)).to be(true)
    expect(collection.data.exists(SecureRandom.uuid)).to be(false)
  end

  it "test_return_list_properties" do
    name_small = "TestReturnList"
    collection = collection_factory(
      name: name_small,
      vector_config: self_provided,
      properties: [
        property.new(name: "ints", data_type: data_type::INT_ARRAY),
        property.new(name: "floats", data_type: data_type::NUMBER_ARRAY),
        property.new(name: "strings", data_type: data_type::TEXT_ARRAY),
        property.new(name: "bools", data_type: data_type::BOOL_ARRAY),
        property.new(name: "dates", data_type: data_type::DATE_ARRAY),
        property.new(name: "uuids", data_type: data_type::UUID_ARRAY)
      ]
    )
    data = {
      "ints" => [1, 2, 3],
      "floats" => [0.1, 0.4, 10.5],
      "strings" => %w[a list of strings],
      "bools" => [true, false, true],
      "dates" => [Time.utc(2012, 2, 9)],
      "uuids" => [SecureRandom.uuid, SecureRandom.uuid]
    }
    collection.data.insert(properties: data)
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties).to eq(data)
  end

  %w[return_properties0 return_properties1].zip([["value"], nil]).each do |rp_id, return_properties|
    { "concepts0" => "hiking", "concepts1" => ["hiking"] }.each do |c_id, concepts|
      { "objects0" => uuid1, "objects1" => uuid1.to_s, "objects2" => [uuid1], "objects3" => [uuid1.to_s] }.each do |o_id, objects|
        { "query0" => "cake", "query1" => ["cake"] }.each do |q_id, query|
          it "test_near_text[#{rp_id}-#{c_id}-#{o_id}-#{q_id}]" do
            skip_if_native!("needs the text2vec-contextionary vectorizer")
            collection = collection_factory(vector_config: contextionary,
                                            properties: [property.new(name: "value", data_type: data_type::TEXT)])

            batch_return = collection.data.insert_many(
              [
                data_object.new(properties: { "value" => "Apple" }, uuid: uuid1),
                data_object.new(properties: { "value" => "Mountain climbing" }),
                data_object.new(properties: { "value" => "apple cake" }),
                data_object.new(properties: { "value" => "cake" })
              ]
            )

            objs = collection.query.near_text(
              query,
              move_to: q::Move.new(force: 1.0, objects: objects),
              move_away: q::Move.new(force: 0.5, concepts: concepts),
              include_vector: true,
              return_properties: return_properties
            ).objects

            expect(objs.length).to eq(4)

            expect(objs[0].uuid).to eq(batch_return.uuids[2])
            expect(objs[0].vector).to include("default")
            expect(objs[0].properties["value"]).to eq("apple cake") unless return_properties.nil?
          end
        end
      end
    end
  end

  it "test_near_text_error" do
    collection = collection_factory(vector_config: self_provided)

    # Python ValueError -> Ruby ArgumentError (raised when building the Move)
    expect { collection.query.near_text("test", move_to: q::Move.new(force: 1.0)) }.to raise_error(ArgumentError)
  end

  it "test_near_text_group_by_argument" do
    dummy = collection_factory(name: "dummy")
    if version_lower_than?(dummy, 1, 27, 0)
      skip('Vectors not passed to GroupByHit in servers for versions < 1.27.0. Therefore `assert "default" in ' \
           "ret.objects[i].vector` fails always.")
    end
    skip_if_native!("needs the text2vec-contextionary vectorizer")

    collection = collection_factory(vector_config: contextionary,
                                    properties: [property.new(name: "value", data_type: data_type::TEXT)])

    batch_return = collection.data.insert_many(
      [
        data_object.new(properties: { "value" => "Apple" }, uuid: uuid1),
        data_object.new(properties: { "value" => "Mountain climbing" }),
        data_object.new(properties: { "value" => "apple cake" }),
        data_object.new(properties: { "value" => "cake" })
      ]
    )

    ret = collection.query.near_text(
      "cake",
      group_by: q::GroupBy.new(prop: "value", number_of_groups: 2, objects_per_group: 100),
      include_vector: true,
      return_properties: ["value"]
    )

    expect(ret.objects.length).to eq(2)
    expect(ret.objects[0].uuid).to eq(batch_return.uuids[3])
    expect(ret.objects[0].vector).to include("default")
    expect(ret.objects[0].belongs_to_group).to eq("cake")
    expect(ret.objects[1].uuid).to eq(batch_return.uuids[2])
    expect(ret.objects[1].vector).to include("default")
    expect(ret.objects[1].belongs_to_group).to eq("apple cake")
  end

  it "test_near_text_limit" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(vector_config: contextionary,
                                    properties: [property.new(name: "value", data_type: data_type::TEXT)])

    batch_return = collection.data.insert_many(
      [
        data_object.new(properties: { "value" => "Apple" }, uuid: uuid1),
        data_object.new(properties: { "value" => "Mountain climbing" }),
        data_object.new(properties: { "value" => "apple cake" }),
        data_object.new(properties: { "value" => "cake" })
      ]
    )

    objects = collection.query.near_text("cake", limit: 2, return_properties: ["value"]).objects

    expect(objects.length).to eq(2)
    expect(objects[0].uuid).to eq(batch_return.uuids[3])
    expect(objects[0].properties["value"]).to eq("cake")
    expect(objects[1].uuid).to eq(batch_return.uuids[2])
    expect(objects[1].properties["value"]).to eq("apple cake")
  end

  it "test_near_text_offset" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(vector_config: contextionary,
                                    properties: [property.new(name: "value", data_type: data_type::TEXT)])

    batch_return = collection.data.insert_many(
      [
        data_object.new(properties: { "value" => "Apple" }, uuid: uuid1),
        data_object.new(properties: { "value" => "Mountain climbing" }),
        data_object.new(properties: { "value" => "apple cake" }),
        data_object.new(properties: { "value" => "cake" })
      ]
    )

    objects = collection.query.near_text("cake", offset: 1, return_properties: ["value"]).objects

    expect(objects.length).to eq(3)
    expect(objects[0].uuid).to eq(batch_return.uuids[2])
    expect(objects[0].properties["value"]).to eq("apple cake")
  end

  %w[path base64 pathlib.Path io.BufferedReader].each do |image_id|
    [[nil, nil], [10.0, nil], [nil, 0.1]].each do |distance, certainty|
      it "test_near_image[#{distance.inspect}-#{certainty.inspect}-#{image_id}]" do
        skip("img2vec-neural removed from CI. This test should go in the e2e-tests repo instead")
      end

      it "test_near_media[#{distance.inspect}-#{certainty.inspect}-#{image_id}]" do
        skip("img2vec-neural removed from CI. This test should go in the e2e-tests repo instead")
      end
    end
  end

  it "test_bad_near_media_input" do
    collection = collection_factory

    expect { collection.query.near_media(42, q::NearMediaType::IMAGE).objects }
      .to raise_error(ex::WeaviateInvalidInputError)
  end

  # Python uses query-specific TypedDicts as return_properties; the Ruby equivalent is the list of their keys.
  (0..4).each do |which_case|
    it "test_return_properties_with_query_specific_typed_dict[#{which_case}]" do
      collection = collection_factory(
        vector_config: self_provided,
        properties: [property.new(name: "int_", data_type: data_type::INT),
                     property.new(name: "ints", data_type: data_type::INT_ARRAY)]
      )
      data = { "int_" => 1, "ints" => [1, 2, 3] }
      collection.data.insert(properties: data)

      data_model0 = ["int_"]
      data_model1 = ["ints"]
      data_model2 = %w[int_ ints]
      data_model3 = ["non_existant"]
      data_model4 = []

      case which_case
      when 0
        objects = collection.query.fetch_objects(return_properties: data_model0).objects
        expect(objects.length).to eq(1)
        expect(objects[0].properties).to eq({ "int_" => 1 })
      when 1
        objects = collection.query.fetch_objects(return_properties: data_model1).objects
        expect(objects.length).to eq(1)
        expect(objects[0].properties).to eq({ "ints" => [1, 2, 3] })
      when 2
        objects = collection.query.fetch_objects(return_properties: data_model2).objects
        expect(objects.length).to eq(1)
        expect(objects[0].properties).to eq(data)
      when 3
        expect { collection.query.fetch_objects(return_properties: data_model3).objects }
          .to raise_error(ex::WeaviateQueryError)
      when 4
        objects = collection.query.fetch_objects(return_properties: data_model4).objects
        expect(objects.length).to eq(1)
        expect(objects[0].properties).to eq({})
      end
    end
  end

  it "test_return_properties_with_general_typed_dict" do
    # Python sets data_model_properties=_Data; Ruby has no typed data models so plain hashes are used.
    collection = collection_factory(
      vector_config: self_provided,
      properties: [property.new(name: "int_", data_type: data_type::INT),
                   property.new(name: "ints", data_type: data_type::INT_ARRAY)]
    )
    collection.data.insert(properties: { "int_" => 1, "ints" => [1, 2, 3] })
    objects = collection.query.fetch_objects.objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["int_"]).to eq(1)
    expect(objects[0].properties["ints"]).to eq([1, 2, 3])
  end

  it "test_return_properties_with_query_specific_typed_dict_overwriting_general_typed_dict" do
    collection = collection_factory(
      vector_config: self_provided,
      properties: [property.new(name: "int_", data_type: data_type::INT),
                   property.new(name: "ints", data_type: data_type::INT_ARRAY)]
    )
    collection.data.insert(properties: { "int_" => 1, "ints" => [1, 2, 3] })
    objects = collection.query.fetch_objects(return_properties: ["int_"]).objects
    expect(objects.length).to eq(1)
    expect(objects[0].properties["int_"]).to eq(1)
    expect(objects[0].properties).not_to include("ints")

    obj = collection.query.fetch_object_by_id(objects[0].uuid, return_properties: ["int_"])
    expect(obj).not_to be_nil
    expect(obj.properties).not_to include("ints")
    expect(obj.properties["int_"]).to eq(1)
  end

  it "test_batch_with_arrays" do
    collection = collection_factory(
      vector_config: self_provided,
      properties: [
        property.new(name: "texts", data_type: data_type::TEXT_ARRAY),
        property.new(name: "ints", data_type: data_type::INT_ARRAY),
        property.new(name: "floats", data_type: data_type::NUMBER_ARRAY),
        property.new(name: "bools", data_type: data_type::BOOL_ARRAY),
        property.new(name: "uuids", data_type: data_type::UUID_ARRAY),
        property.new(name: "dates", data_type: data_type::DATE_ARRAY)
      ]
    )

    objects_in = [
      data_object.new(
        properties: {
          "texts" => %w[first second],
          "ints" => [1, 2],
          "floats" => [1, 2], # send floats as int
          "bools" => [true, true, false],
          "dates" => [date1, date3],
          "uuids" => [uuid1, uuid3]
        }
      ),
      data_object.new(
        properties: {
          "texts" => %w[third fourth],
          "ints" => [3, 4, 5],
          "floats" => [1.2, 2],
          "bools" => [false, false],
          "dates" => [date2, date3, date1],
          "uuids" => [uuid2, uuid1]
        }
      )
    ]

    ret = collection.data.insert_many(objects_in)

    expect(ret.has_errors).to be(false)

    ret.uuids.values.each_with_index do |obj_id, i|
      obj_out = collection.query.fetch_object_by_id(obj_id)
      expect(obj_out).not_to be_nil

      objects_in[i].properties.each do |prop, val|
        expect(obj_out.properties[prop]).to eq(val)
      end
    end
  end

  [
    ["sort0", -> { q::Sort.by_property("name", ascending: true) }, [0, 1, 2]],
    ["sort1", -> { q::Sort.by_property("name", ascending: false) }, [2, 1, 0]],
    ["sort2", -> { q::Sort.by_property("age", ascending: false).by_property("name", ascending: true) }, [1, 2, 0]],
    ["sort3", -> { q::Sort.by_id(ascending: true) }, [0, 1, 2]],
    ["sort4", -> { q::Sort.by_id(ascending: false) }, [2, 1, 0]],
    ["sort5", -> { q::Sort.by_creation_time(ascending: true) }, [0, 1, 2]],
    ["sort6", -> { q::Sort.by_creation_time(ascending: false) }, [2, 1, 0]],
    ["sort7", -> { q::Sort.by_update_time(ascending: true) }, [0, 1, 2]],
    ["sort8", -> { q::Sort.by_update_time(ascending: false) }, [2, 1, 0]]
  ].each do |sort_id, sort_maker, expected|
    it "test_sort[#{sort_id}-#{expected}]" do
      sort = sort_maker.call
      collection = collection_factory(
        vector_config: self_provided,
        properties: [property.new(name: "age", data_type: data_type::INT),
                     property.new(name: "name", data_type: data_type::TEXT)]
      )

      u1 = collection.data.insert(properties: { "name" => "A", "age" => 20 }, uuid: "#{uuid1[0...-1]}1")
      sleep(0.01)
      u2 = collection.data.insert(properties: { "name" => "B", "age" => 22 }, uuid: "#{uuid1[0...-1]}2")
      sleep(0.01)
      u3 = collection.data.insert(properties: { "name" => "C", "age" => 22 }, uuid: "#{uuid1[0...-1]}3")

      uuids_from = [u1, u2, u3]

      objects = collection.query.fetch_objects(sort: sort).objects
      expect(objects.length).to eq(expected.length)

      expected_uuids = expected.map { |result| uuids_from[result] }
      object_uuids = objects.map(&:uuid)
      expect(object_uuids).to eq(expected_uuids)
    end
  end

  it "test_optional_ref_returns" do
    ref_collection = collection_factory(name: "target", vector_config: self_provided,
                                        properties: [property.new(name: "text", data_type: data_type::TEXT)])
    uuid_to1 = ref_collection.data.insert(properties: { "text" => "ref text" })

    collection = collection_factory(
      name: "source",
      references: [reference_property.new(name: "ref", target_collection: ref_collection.name)],
      vector_config: self_provided
    )
    collection.data.insert({}, references: { "ref" => uuid_to1 })

    objects = collection.query.fetch_objects(return_references: [q::QueryReference.new(link_on: "ref")]).objects

    expect(objects[0].references["ref"].objects[0].properties["text"]).to eq("ref text")
    expect(objects[0].references["ref"].objects[0].uuid).not_to be_nil
  end

  ["bob", ""].each do |value|
    it "test_return_properties_with_type_hint_generic[#{value}]" do
      # Python reads the collection with a Dict[str, str] generic; Ruby has no typed data models.
      dummy = collection_factory(vector_config: self_provided,
                                 properties: [property.new(name: "name", data_type: data_type::TEXT)])
      collection = collection_factory_get(dummy.name)
      collection.data.insert(properties: { "name" => value })
      objects = collection.query.fetch_objects.objects
      expect(objects.length).to eq(1)
      expect(objects[0].properties["name"]).to eq(value)
    end
  end

  it "test_return_blob_property" do
    collection = collection_factory(properties: [property.new(name: "blob", data_type: data_type::BLOB)])
    uuid = collection.data.insert({ "blob" => logo })
    collection.data.insert_many([{ "blob" => logo }])
    obj = collection.query.fetch_object_by_id(uuid, return_properties: ["blob"])
    objs = collection.query.fetch_objects(return_properties: ["blob"]).objects
    expect(objs.length).to eq(2)
    expect(obj.properties["blob"]).to eq(logo)
    expect(objs[0].properties["blob"]).to eq(logo)
    expect(objs[1].properties["blob"]).to eq(logo)
  end

  it "test_collection_shards" do
    collection = collection_factory
    shards = collection.shards

    expect(shards.length).to eq(1)
    expect(shards[0].collection).to eq(collection.name)
    expect(shards[0].name).not_to be_nil
    expect(shards[0].object_count).to eq(0)
  end

  it "test_return_phone_number_property" do
    collection = collection_factory(properties: [property.new(name: "phone", data_type: data_type::PHONE_NUMBER)])
    u1 = collection.data.insert({ "phone" => phone_number.new(number: "+441612345000") })
    u2 = collection.data.insert_many(
      [{ "phone" => phone_number.new(default_country: "GB", number: "01612345000") }]
    ).uuids[0]
    obj1 = collection.query.fetch_object_by_id(u1, return_properties: ["phone"])
    objs = collection.query.fetch_objects(return_properties: ["phone"]).objects
    obj2 = objs.find { |obj| obj.uuid == u2 }
    expect(objs.length).to eq(2)
    expect(obj1.properties["phone"]).to be_a(Weaviate::Classes::Data::PhoneNumberType)
    expect(obj1.properties["phone"].number).to eq("+441612345000")
    expect(obj1.properties["phone"].valid).to be(true)
    expect(obj1.properties["phone"].international_formatted).to eq("+44 161 234 5000")
    expect(obj2.properties["phone"]).to be_a(Weaviate::Classes::Data::PhoneNumberType)
    expect(obj2.properties["phone"].number).to eq("01612345000")
    expect(obj2.properties["phone"].valid).to be(true)
    expect(obj2.properties["phone"].international_formatted).to eq("+44 161 234 5000")
  end

  it "test_return_phone_number_property_wrong_type" do
    collection = collection_factory(properties: [property.new(name: "phone", data_type: data_type::PHONE_NUMBER)])
    u1 = collection.data.insert({ "phone" => phone_number.new(number: "+441612345000") })
    obj1 = collection.query.fetch_object_by_id(u1)
    expect { collection.data.insert({ "phone" => obj1.properties["phone"] }) }
      .to raise_error(ex::WeaviateInvalidInputError)
  end

  it "test_double_insert_with_same_uuid" do
    collection = collection_factory
    u1 = collection.data.insert({})
    expect { collection.data.insert({}, uuid: u1) }.to raise_error(ex::UnexpectedStatusCodeError)
  end

  it "test_nil_return" do
    collection = collection_factory(properties: [property.new(name: "a", data_type: data_type::TEXT),
                                                 property.new(name: "b", data_type: data_type::TEXT)])

    collection.data.insert({ "a" => "a1" })
    objs = collection.query.fetch_objects(return_properties: %w[a b]).objects
    expect(objs.length).to eq(1)
    expect(objs[0].properties["a"]).to eq("a1")
    expect(objs[0].properties["b"]).to be_nil if objs[0].properties.key?("b") # change this when server version bumps to 1.24.0
  end

  it "test_none_query_hybrid_bm25" do
    skip_if_native!("needs the text2vec-contextionary vectorizer")
    collection = collection_factory(properties: [property.new(name: "text", data_type: data_type::TEXT)],
                                    vector_config: contextionary)

    collection.data.insert({ "text" => "banana" })
    collection.data.insert({ "text" => "dog" })
    collection.data.insert({ "text" => "different concept" })

    hybrid_objs = collection.query.hybrid(nil, vector: nil, return_metadata: q::MetadataQuery.full).objects
    expect(hybrid_objs.length).to eq(3)
    expect(hybrid_objs.all? { |obj| !obj.metadata.score.nil? && obj.metadata.score == 0.0 }).to be(true)

    bm25_objs = collection.query.bm25(nil, return_metadata: q::MetadataQuery.full).objects
    expect(bm25_objs.length).to eq(3)
    expect(bm25_objs.all? { |obj| !obj.metadata.score.nil? && obj.metadata.score == 0.0 }).to be(true)
  end

  it "test_bm25_operators" do
    collection = collection_factory(properties: [property.new(name: "name", data_type: data_type::TEXT)],
                                    vectorizer_config: configure::Vectorizer.none)

    if version_lower_than?(collection, 1, 31, 0)
      skip("bm25 operators are only supported in versions higher than 1.31.0")
    end

    u1 = collection.data.insert({ "name" => "banana one" })
    u2 = collection.data.insert({ "name" => "banana two" })
    u3 = collection.data.insert({ "name" => "banana three" })
    u4 = collection.data.insert({ "name" => "banana four" })

    objs = collection.query.bm25("banana two", operator: q::BM25Operator.or_(minimum_match: 1))
    expect(objs.objects.length).to eq(4)
    expect(objs.objects[0].uuid).to eq(u2)
    expect(objs.objects[1..].map(&:uuid).sort).to eq([u1, u3, u4].sort)
  end

  it "test_bm25_operator_and_cross" do
    collection = collection_factory(
      properties: [property.new(name: "title", data_type: data_type::TEXT),
                   property.new(name: "body", data_type: data_type::TEXT)],
      vectorizer_config: configure::Vectorizer.none
    )

    min_versions = Weaviate::Collections::Grpc::BM25_AND_CROSS_MIN_VERSIONS
    unless collection.instance_variable_get(:@connection).weaviate_version.is_at_least_any(*min_versions)
      skip("bm25 cross-property AND requires #{Weaviate::Collections::Grpc::BM25_AND_CROSS_MIN_VERSIONS_STR}")
    end

    # Neither of `split_across`'s properties holds both tokens, so only cross-property AND matches it.
    split_across = collection.data.insert({ "title" => "banana", "body" => "split" })
    single_property = collection.data.insert({ "title" => "banana split", "body" => "dessert" })
    collection.data.insert({ "title" => "banana", "body" => "bread" })

    objs = collection.query.bm25("banana split", operator: q::BM25Operator.and_cross)
    expect(objs.objects.map(&:uuid).sort).to eq([split_across, single_property].sort)
  end
end
