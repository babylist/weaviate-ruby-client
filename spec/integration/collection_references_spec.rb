# frozen_string_literal: true

# Port of integration/test_collection_references.py
#
# Ruby UUIDs are Strings, so the Python parametrizations over `uuid.UUID` vs `str` inputs pass the same
# String value; they are kept so every Python case has a Ruby counterpart.
RSpec.describe "collection references", :integration do
  include Batch3Helpers

  config = Weaviate::Classes::Config
  query = Weaviate::Classes::Query
  data = Weaviate::Classes::Data

  to_uuid = "8ad0d33c-8db1-4437-87f3-72161ca2a51a"
  to_uuid2 = "577887c1-4c6b-5594-aa62-f0c17883d9cf"

  uuid_inputs = { "uuid" => to_uuid, "str" => to_uuid }

  uuid_inputs.each do |add_label, add|
    uuid_inputs.each do |delete_label, delete|
      it "test_reference_add_delete_replace[#{delete_label}-#{add_label}]" do
        ref_collection = collection_factory(name: "Target", vectorizer_config: config::Configure::Vectorizer.none)
        ref_collection.data.insert(properties: {}, uuid: to_uuid)
        collection = collection_factory(
          references: [config::ReferenceProperty::MultiTarget.new(name: "ref",
                                                                  target_collections: [ref_collection.name])],
          vectorizer_config: config::Configure::Vectorizer.none
        )

        uuid_from1 = collection.data.insert({}, uuid: random_uuid)
        uuid_from2 = collection.data.insert({}, references: { "ref" => to_uuid }, uuid: random_uuid)
        collection.data.reference_add(from_uuid: uuid_from1, from_property: "ref", to: add)

        collection.data.reference_delete(from_uuid: uuid_from1, from_property: "ref", to: delete)
        expect(
          collection.query.fetch_object_by_id(uuid_from1, return_references: query::QueryReference.new(link_on: "ref"))
            .references["ref"].objects.length
        ).to eq(0)

        collection.data.reference_add(from_uuid: uuid_from2, from_property: "ref", to: add)
        obj = collection.query.fetch_object_by_id(uuid_from2,
                                                  return_references: query::QueryReference.new(link_on: "ref"))
        expect(obj).not_to be_nil
        expect(obj.references["ref"].objects.length).to eq(2)
        expect(obj.references["ref"].objects.map(&:uuid)).to include(to_uuid)

        collection.data.reference_replace(from_uuid: uuid_from2, from_property: "ref", to: [])
        expect(
          collection.query.fetch_object_by_id(uuid_from2, return_references: query::QueryReference.new(link_on: "ref"))
            .references["ref"].objects.length
        ).to eq(0)
      end
    end
  end

  it "test_reference_add_delete_replace_multi_target" do
    ref_collection = collection_factory(name: "Target", vectorizer_config: config::Configure::Vectorizer.none)
    ref_collection.data.insert(properties: {}, uuid: to_uuid)
    collection = collection_factory(
      references: [config::ReferenceProperty::MultiTarget.new(name: "ref", target_collections: [ref_collection.name])],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    uuid_from1 = collection.data.insert({}, uuid: random_uuid)
    uuid_from2 = collection.data.insert({}, references: { "ref" => to_uuid }, uuid: random_uuid)
    collection.data.reference_add(
      from_uuid: uuid_from1, from_property: "ref",
      to: data::ReferenceToMulti.new(target_collection: ref_collection.name, uuids: to_uuid)
    )

    collection.data.reference_delete(
      from_uuid: uuid_from1, from_property: "ref",
      to: data::ReferenceToMulti.new(target_collection: ref_collection.name, uuids: to_uuid)
    )
    expect(
      collection.query.fetch_object_by_id(uuid_from1, return_references: query::QueryReference.new(link_on: "ref"))
        .references["ref"].objects.length
    ).to eq(0)

    collection.data.reference_add(
      from_uuid: uuid_from2, from_property: "ref",
      to: data::ReferenceToMulti.new(target_collection: ref_collection.name, uuids: to_uuid)
    )
    obj = collection.query.fetch_object_by_id(uuid_from2, return_references: query::QueryReference.new(link_on: "ref"))
    expect(obj).not_to be_nil
    expect(obj.references["ref"].objects.length).to eq(2)
    expect(obj.references["ref"].objects.map(&:uuid)).to include(to_uuid)

    collection.data.reference_replace(
      from_uuid: uuid_from2, from_property: "ref",
      to: data::ReferenceToMulti.new(target_collection: ref_collection.name, uuids: [])
    )
    expect(
      collection.query.fetch_object_by_id(uuid_from2, return_references: query::QueryReference.new(link_on: "ref"))
        .references["ref"].objects.length
    ).to eq(0)
  end

  multiple_uuid_inputs = {
    "to0" => [to_uuid, to_uuid],
    "to1" => data::ReferenceToMulti.new(target_collection: "Target", uuids: [to_uuid, to_uuid])
  }

  multiple_uuid_inputs.each do |label, to|
    it "test_reference_add_multiple_uuids_error[#{label}]" do
      ref_collection = collection_factory(name: "Target", vectorizer_config: config::Configure::Vectorizer.none)
      ref_collection.data.insert(properties: {}, uuid: to_uuid)
      collection = collection_factory(
        references: [config::ReferenceProperty.new(name: "ref", target_collection: ref_collection.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )
      uuid_from1 = collection.data.insert({}, uuid: random_uuid)
      expect do
        collection.data.reference_add(from_uuid: uuid_from1, from_property: "ref", to: to)
      end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    end
  end

  multiple_uuid_inputs.each do |label, to|
    it "test_reference_delete_multiple_uuids_error[#{label}]" do
      ref_collection = collection_factory(name: "Target", vectorizer_config: config::Configure::Vectorizer.none)
      ref_collection.data.insert(properties: {}, uuid: to_uuid)
      collection = collection_factory(
        references: [config::ReferenceProperty.new(name: "ref", target_collection: ref_collection.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )
      uuid_from1 = collection.data.insert({}, uuid: random_uuid)
      expect do
        collection.data.reference_delete(from_uuid: uuid_from1, from_property: "ref", to: to)
      end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
    end
  end

  it "test_mono_references_grpc" do
    a = collection_factory(
      name: "A",
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
    )
    uuid_a1 = a.data.insert(properties: { "Name" => "A1" })
    uuid_a2 = a.data.insert(properties: { "Name" => "A2" })

    a_objs = a.query.bm25("A1", return_properties: "name").objects
    expect(a_objs[0].collection).to eq(a.name)
    expect(a_objs[0].properties["name"]).to eq("A1")

    b = collection_factory(
      name: "B",
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      references: [config::ReferenceProperty.new(name: "a", target_collection: a.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    uuid_b = b.data.insert({ "Name" => "B" }, references: { "a" => uuid_a1 })
    b.data.reference_add(from_uuid: uuid_b, from_property: "a", to: uuid_a2)

    b_objs = b.query.bm25(
      "B", return_references: query::QueryReference.new(link_on: "a", return_properties: ["name"])
    ).objects
    expect(b_objs[0].references["a"].objects[0].collection).to eq(a.name)
    expect(b_objs[0].references["a"].objects[0].properties["name"]).to eq("A1")
    expect(b_objs[0].references["a"].objects[0].uuid).to eq(uuid_a1)
    expect(b_objs[0].references["a"].objects[1].collection).to eq(a.name)
    expect(b_objs[0].references["a"].objects[1].properties["name"]).to eq("A2")
    expect(b_objs[0].references["a"].objects[1].uuid).to eq(uuid_a2)

    c = collection_factory(
      name: "C",
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      references: [config::ReferenceProperty.new(name: "b", target_collection: b.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    c.data.insert({ "Name" => "find me" }, references: { "b" => uuid_b })

    c_objs = c.query.bm25(
      "find",
      return_properties: "name",
      return_references: query::QueryReference.new(
        link_on: "b",
        return_properties: "name",
        return_metadata: query::MetadataQuery.new(last_update_time: true),
        return_references: query::QueryReference.new(link_on: "a", return_properties: "name")
      )
    ).objects
    expect(c_objs[0].collection).to eq(c.name)
    expect(c_objs[0].properties["name"]).to eq("find me")
    expect(c_objs[0].references["b"].objects[0].collection).to eq(b.name)
    expect(c_objs[0].references["b"].objects[0].properties["name"]).to eq("B")
    expect(c_objs[0].references["b"].objects[0].metadata.last_update_time).not_to be_nil
    expect(c_objs[0].references["b"].objects[0].references["a"].objects[0].collection).to eq(a.name)
    expect(c_objs[0].references["b"].objects[0].references["a"].objects[0].properties["name"]).to eq("A1")
    expect(c_objs[0].references["b"].objects[0].references["a"].objects[1].collection).to eq(a.name)
    expect(c_objs[0].references["b"].objects[0].references["a"].objects[1].properties["name"]).to eq("A2")
  end

  # Python's typed data models (TypedDict generics) have no Ruby equivalent: the four `level`
  # variants (generics on the collection vs. on the query) all collapse to the explicit
  # QueryReference form below, which is what the generics are translated to.
  %w[col-col col-query query-col query-query].each do |level|
    it "test_mono_references_grpc_with_generics[#{level}]" do
      skip_if_native!("requires text2vec-contextionary")
      vectorizer = config::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false)
      dummy_a = collection_factory(
        name: "a", vectorizer_config: vectorizer,
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
      )
      a = collection_factory_get(dummy_a.name)
      uuid_a1 = a.data.insert({ "name" => "A1" })
      uuid_a2 = a.data.insert({ "name" => "A2" })

      dummy_b = collection_factory(
        name: "B",
        properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
        references: [config::ReferenceProperty.new(name: "a", target_collection: a.name)],
        vectorizer_config: vectorizer
      )
      b = collection_factory_get(dummy_b.name)
      uuid_b = b.data.insert(properties: { "name" => "B" }, references: { "a" => uuid_a1 })
      b.data.reference_add(from_uuid: uuid_b, from_property: "a", to: uuid_a2)

      b_refs = query::QueryReference.new(
        link_on: "a", return_properties: ["name"],
        return_metadata: query::MetadataQuery.new(creation_time: true), include_vector: true
      )
      b_objs = b.query.bm25("B", return_references: b_refs).objects
      expect(b_objs[0].collection).to eq(b.name)
      expect(b_objs[0].properties["name"]).to eq("B")
      expect(b_objs[0].references["a"].objects[0].collection).to eq(a.name)
      expect(b_objs[0].references["a"].objects[0].properties["name"]).to eq("A1")
      expect(b_objs[0].references["a"].objects[0].uuid).to eq(uuid_a1)
      expect(b_objs[0].references["a"].objects[0].references).to be_nil
      expect(b_objs[0].references["a"].objects[1].collection).to eq(a.name)
      expect(b_objs[0].references["a"].objects[1].properties["name"]).to eq("A2")
      expect(b_objs[0].references["a"].objects[1].uuid).to eq(uuid_a2)
      expect(b_objs[0].references["a"].objects[1].references).to be_nil

      dummy_c = collection_factory(
        name: "C",
        properties: [
          config::Property.new(name: "Name", data_type: config::DataType::TEXT),
          config::Property.new(name: "Age", data_type: config::DataType::INT)
        ],
        references: [config::ReferenceProperty.new(name: "b", target_collection: b.name)],
        vectorizer_config: vectorizer
      )
      c = collection_factory_get(dummy_c.name)
      c.data.insert(properties: { "name" => "find me" }, references: { "b" => uuid_b })

      c_refs = query::QueryReference.new(link_on: "b", return_properties: ["name"], return_references: b_refs)
      c_objs = collection_factory_get(c.name).query.bm25(
        "find", include_vector: true, return_properties: ["name"], return_references: c_refs
      ).objects
      expect(c_objs[0].collection).to eq(c.name)
      expect(c_objs[0].properties["name"]).to eq("find me")
      expect(c_objs[0].uuid).not_to be_nil
      expect(c_objs[0].vector).to include("default")
      expect(c_objs[0].properties["not_specified"]).to be_nil
      b_obj = c_objs[0].references["b"].objects[0]
      expect(b_obj.collection).to eq(b.name)
      expect(b_obj.properties["name"]).to eq("B")
      expect(b_obj.uuid).to eq(uuid_b)
      expect(b_obj.vector).not_to include("default")
      [[uuid_a1, "A1"], [uuid_a2, "A2"]].each_with_index do |(uid, name), i|
        a_obj = b_obj.references["a"].objects[i]
        expect(a_obj.collection).to eq(a.name)
        expect(a_obj.properties["name"]).to eq(name)
        expect(a_obj.uuid).to eq(uid)
        expect(a_obj.metadata.creation_time).not_to be_nil
        expect(a_obj.vector).to include("default")
      end
    end
  end

  def multi_reference_collections
    config = Weaviate::Classes::Config
    data = Weaviate::Classes::Data
    a = collection_factory(
      name: "A", vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
    )
    uuid_a = a.data.insert(properties: { "Name" => "A" })

    b = collection_factory(
      name: "B", vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
    )
    uuid_b = b.data.insert({ "Name" => "B" })

    c = collection_factory(
      name: "C",
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      references: [config::ReferenceProperty::MultiTarget.new(name: "ref", target_collections: [a.name, b.name])],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    c.data.insert({ "Name" => "first" },
                  references: { "ref" => data::ReferenceToMulti.new(uuids: uuid_a, target_collection: a.name) })
    c.data.insert({ "Name" => "second" },
                  references: { "ref" => data::ReferenceToMulti.new(uuids: uuid_b, target_collection: b.name) })
    [a, b, c]
  end

  it "test_multi_references_grpc" do
    a, b, c = multi_reference_collections

    objects = c.query.bm25(
      "first",
      return_properties: "name",
      return_references: query::QueryReference::MultiTarget.new(
        link_on: "ref", target_collection: a.name, return_properties: ["name"],
        return_metadata: query::MetadataQuery.new(last_update_time: true)
      )
    ).objects
    expect(objects[0].collection).to eq(c.name)
    expect(objects[0].properties["name"]).to eq("first")
    expect(objects[0].references["ref"].objects.length).to eq(1)
    expect(objects[0].references["ref"].objects[0].collection).to eq(a.name)
    expect(objects[0].references["ref"].objects[0].properties["name"]).to eq("A")
    expect(objects[0].references["ref"].objects[0].metadata.last_update_time).not_to be_nil

    objects = c.query.bm25(
      "second",
      return_properties: "name",
      return_references: query::QueryReference::MultiTarget.new(
        link_on: "ref", target_collection: b.name, return_properties: ["name"],
        return_metadata: query::MetadataQuery.new(last_update_time: true)
      )
    ).objects
    expect(objects[0].collection).to eq(c.name)
    expect(objects[0].properties["name"]).to eq("second")
    expect(objects[0].references["ref"].objects.length).to eq(1)
    expect(objects[0].references["ref"].objects[0].collection).to eq(b.name)
    expect(objects[0].references["ref"].objects[0].properties["name"]).to eq("B")
    expect(objects[0].references["ref"].objects[0].metadata.last_update_time).not_to be_nil
  end

  # Typed data models are not supported in Ruby: the CProps / CRefsA / CRefsB TypedDicts translate to
  # return_properties: ["name"] and a QueryReference::MultiTarget with last_update_time metadata.
  it "test_multi_references_grpc_with_generics" do
    a, b, c = multi_reference_collections

    c_refs_a = query::QueryReference::MultiTarget.new(
      link_on: "ref", target_collection: a.name, return_properties: ["name"],
      return_metadata: query::MetadataQuery.new(last_update_time: true)
    )
    c_refs_b = query::QueryReference::MultiTarget.new(
      link_on: "ref", target_collection: b.name, return_properties: ["name"],
      return_metadata: query::MetadataQuery.new(last_update_time: true)
    )

    objects = c.query.bm25("first", return_properties: ["name"], return_references: c_refs_a).objects
    expect(objects[0].collection).to eq(c.name)
    expect(objects[0].properties["name"]).to eq("first")
    expect(objects[0].references["ref"].objects.length).to eq(1)
    expect(objects[0].references["ref"].objects[0].collection).to eq(a.name)
    expect(objects[0].references["ref"].objects[0].properties["name"]).to eq("A")
    expect(objects[0].references["ref"].objects[0].metadata.last_update_time).not_to be_nil

    objects = c.query.bm25("second", return_properties: ["name"], return_references: c_refs_b).objects
    expect(objects[0].collection).to eq(c.name)
    expect(objects[0].properties["name"]).to eq("second")
    expect(objects[0].references["ref"].objects.length).to eq(1)
    expect(objects[0].references["ref"].objects[0].collection).to eq(b.name)
    expect(objects[0].references["ref"].objects[0].properties["name"]).to eq("B")
    expect(objects[0].references["ref"].objects[0].metadata.last_update_time).not_to be_nil
  end

  it "test_references_batch" do
    ref_collection = collection_factory(
      name: "To", vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "number", data_type: config::DataType::INT)]
    )
    num_objects = 10

    uuids_to = ref_collection.data.insert_many(
      Array.new(num_objects) { |i| data::DataObject.new(properties: { "number" => i }) }
    ).uuids.values
    collection = collection_factory(
      name: "From",
      properties: [config::Property.new(name: "num", data_type: config::DataType::INT)],
      references: [config::ReferenceProperty.new(name: "ref", target_collection: ref_collection.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    uuids_from = collection.data.insert_many(
      Array.new(num_objects) { |i| data::DataObject.new(properties: { "num" => i }) }
    ).uuids.values

    # use both ways of adding batch-references in two calls to preserve order:
    # - single points to an object with the same value as property
    # - multi always points to the first 3 objects
    batch_return = collection.data.reference_add_many(
      Array.new(num_objects) do |i|
        data::DataReference.new(from_property: "ref", from_uuid: uuids_from[i], to_uuid: uuids_to[i])
      end
    )
    expect(batch_return.has_errors).to be(false)

    batch_return = collection.data.reference_add_many(
      Array.new(num_objects) do |i|
        data::DataReference.new(from_property: "ref", from_uuid: uuids_from[i], to_uuid: uuids_to[0, 3])
      end
    )
    expect(batch_return.has_errors).to be(false)

    objects = collection.query.fetch_objects(
      return_properties: ["num"], return_references: [query::QueryReference.new(link_on: "ref")]
    ).objects

    objects.each do |obj|
      expect(obj.properties["num"]).to eq(obj.references["ref"].objects[0].properties["number"])
      expect(uuids_to).to include(obj.references["ref"].objects[0].uuid)
      expect(obj.references["ref"].objects.length).to eq(4)
      refs = Array.new(3) { |j| obj.references["ref"].objects[j + 1].properties["number"] }.sort
      expect(refs).to eq([0, 1, 2])
    end
  end

  it "test_batch_reference_multi_target" do
    to_collection = collection_factory(
      name: "To", vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "number", data_type: config::DataType::INT)]
    )
    from_collection = collection_factory(
      name: "From", vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "num", data_type: config::DataType::INT)]
    )
    from_collection.config.add_reference(
      config::ReferenceProperty::MultiTarget.new(name: "ref",
                                                 target_collections: [to_collection.name, from_collection.name])
    )

    num_objects = 5

    uuids_to = to_collection.data.insert_many(
      Array.new(num_objects) { |i| data::DataObject.new(properties: { "number" => i }) }
    ).uuids.values
    uuids_from = from_collection.data.insert_many(
      Array.new(num_objects) { |i| data::DataObject.new(properties: { "num" => i }) }
    ).uuids.values

    # add to to_collection
    batch_return = from_collection.data.reference_add_many(
      Array.new(num_objects) do |i|
        data::DataReference::MultiTarget.new(from_property: "ref", from_uuid: uuids_from[i], to_uuid: uuids_to[i],
                                             target_collection: to_collection.name)
      end
    )
    expect(batch_return.has_errors).to be(false)

    # add to from_collection
    batch_return = from_collection.data.reference_add_many(
      Array.new(num_objects) do |i|
        data::DataReference::MultiTarget.new(from_property: "ref", from_uuid: uuids_from[i],
                                             to_uuid: uuids_from[i], target_collection: from_collection.name)
      end
    )
    expect(batch_return.has_errors).to be(false)

    objects_with_to_ref = from_collection.query.fetch_objects(
      return_properties: ["num"],
      return_references: [query::QueryReference::MultiTarget.new(link_on: "ref",
                                                                 target_collection: to_collection.name)]
    ).objects
    objects_with_to_ref.each do |obj|
      expect(obj.properties["num"]).to eq(obj.references["ref"].objects[0].properties["number"])
    end

    objects_with_from_ref = from_collection.query.fetch_objects(
      return_properties: ["num"],
      return_references: [query::QueryReference::MultiTarget.new(link_on: "ref",
                                                                 target_collection: from_collection.name)]
    ).objects
    objects_with_from_ref.each do |obj|
      expect(obj.properties["num"]).to eq(obj.references["ref"].objects[0].properties["num"])
    end
  end

  it "test_insert_many_with_refs" do
    collection = collection_factory(
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    collection.config.add_reference(config::ReferenceProperty.new(name: "self", target_collection: collection.name))

    uuid1 = collection.data.insert({ "name" => "A" })
    uuid2 = collection.data.insert({ "name" => "B" })

    batch_return = collection.data.insert_many(
      [
        data::DataObject.new(properties: { "name" => "C" }, references: { "self" => uuid1 }),
        data::DataObject.new(properties: { "name" => "D" }, references: { "self" => [uuid1, uuid2] }),
        data::DataObject.new(properties: { "name" => "E" }, references: { "self" => uuid1 }),
        data::DataObject.new(properties: { "name" => "F" }, references: { "self" => [uuid1, uuid2] })
      ]
    )
    expect(batch_return.has_errors).to be(false)

    collection.query.fetch_objects(
      return_properties: ["name"], return_references: query::QueryReference.new(link_on: "self")
    ).objects.each do |obj|
      if %w[A B].include?(obj.properties["name"])
        expect(obj.references).to eq({})
      else
        expect(obj.references).not_to be_nil
        case obj.properties["name"]
        when "C", "E"
          expect(obj.references["self"].objects[0].uuid).to eq(uuid1)
        when "D", "F"
          expect(obj.references["self"].objects[0].uuid).to eq(uuid1)
          expect(obj.references["self"].objects[1].uuid).to eq(uuid2)
        end
      end
    end
  end

  it "test_references_batch_with_errors" do
    to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)

    collection = collection_factory(
      name: "From",
      properties: [config::Property.new(name: "num", data_type: config::DataType::INT)],
      references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    batch_return = collection.data.reference_add_many(
      [data::DataReference.new(from_property: "doesNotExist", from_uuid: random_uuid, to_uuid: random_uuid)]
    )
    expect(batch_return.has_errors).to be(true)
    expect(batch_return.errors).to include(0)
  end

  it "test_object_without_references" do
    to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)

    source = collection_factory(
      name: "From",
      references: [
        config::ReferenceProperty.new(name: "ref_partial", target_collection: to.name),
        config::ReferenceProperty.new(name: "ref_full", target_collection: to.name)
      ],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    uuid_to = to.data.insert(properties: {})

    uuid_from1 = source.data.insert(references: { "ref_partial" => uuid_to, "ref_full" => uuid_to }, properties: {})
    uuid_from2 = source.data.insert(references: { "ref_full" => uuid_to }, properties: {})

    return_references = [query::QueryReference.new(link_on: "ref_full"),
                         query::QueryReference.new(link_on: "ref_partial")]
    obj1 = source.query.fetch_object_by_id(uuid_from2, return_references: return_references)
    expect(obj1.references).to include("ref_full")
    expect(obj1.references).not_to include("ref_partial")
    expect(obj1.collection).to eq(source.name)

    obj2 = source.query.fetch_object_by_id(uuid_from1, return_references: return_references)
    expect(obj2.references).to include("ref_full", "ref_partial")
    expect(obj2.collection).to eq(source.name)
  end

  it "test_ref_case_sensitivity" do
    to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)

    source = collection_factory(
      name: "From",
      references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )

    # added as upper-case UUID
    uuid_upper_str = "4E5CD755-4F43-44C5-B23C-0C7D6F6C21E6"
    to.data.insert(uuid: uuid_upper_str, properties: {})

    # adding a ref as lower-case UUID should work
    from1 = source.data.insert(properties: {}, references: { "ref" => uuid_upper_str.downcase })

    # try to add as upper-case UUID via different methods
    from2 = source.data.insert(properties: {}, references: { "ref" => uuid_upper_str })
    from3 = source.data.insert(properties: {})
    source.data.reference_add(from_uuid: from3, from_property: "ref", to: uuid_upper_str)

    from4 = source.data.insert(properties: {})
    source.data.reference_add_many(
      [data::DataReference.new(from_uuid: from4, from_property: "ref", to_uuid: uuid_upper_str)]
    )

    from5 = source.data.insert_many(
      [data::DataObject.new(properties: {}, references: { "ref" => uuid_upper_str })]
    ).uuids[0]

    [from1, from2, from3, from4, from5].each do |uid|
      obj = source.query.fetch_object_by_id(uid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references).to include("ref")
    end
  end

  it "test_empty_return_reference" do
    to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
    source = collection_factory(
      name: "From",
      references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
      vectorizer_config: config::Configure::Vectorizer.none
    )
    uuid_source = source.data.insert(properties: {})
    obj = source.query.fetch_object_by_id(uuid_source,
                                          return_references: [query::QueryReference.new(link_on: "ref")])
    expect(obj.references).to eq({})
  end

  ref_inputs = { "to_uuid0" => to_uuid, "to_uuid1" => to_uuid, "to_uuid2" => [to_uuid], "to_uuid3" => [to_uuid] }

  ref_inputs.each do |label, input|
    it "test_refs_different_input_insert[#{label}]" do
      to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
      to.data.insert(properties: {}, uuid: to_uuid)

      source = collection_factory(
        name: "From",
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      from_uuid = source.data.insert(properties: {}, references: { "ref" => input })
      obj = source.query.fetch_object_by_id(from_uuid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid)
    end
  end

  ref_inputs.each do |label, input|
    it "test_refs_different_input_insert_many[#{label}]" do
      to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
      to.data.insert(properties: {}, uuid: to_uuid)

      source = collection_factory(
        name: "From",
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )
      source.config.add_reference(
        config::ReferenceProperty::MultiTarget.new(name: "multi", target_collections: [to.name, source.name])
      )

      from_uuid = source.data.insert_many([data::DataObject.new(properties: {}, references: { "ref" => input })])
      expect(from_uuid.has_errors).to be(false)
      expect(from_uuid.uuids.length).to eq(1)
      obj = source.query.fetch_object_by_id(from_uuid.uuids[0],
                                            return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid)

      from_uuid4 = source.data.insert_many(
        [
          data::DataObject.new(
            properties: {},
            references: { "multi" => data::ReferenceToMulti.new(uuids: to_uuid, target_collection: to.name) }
          )
        ]
      )
      expect(from_uuid4.has_errors).to be(false)
      expect(from_uuid4.uuids.length).to eq(1)
      obj = source.query.fetch_object_by_id(
        from_uuid4.uuids[0],
        return_references: [query::QueryReference::MultiTarget.new(link_on: "multi", target_collection: to.name)]
      )
      expect(obj.references["multi"].objects[0].uuid).to eq(to_uuid)
    end
  end

  { "to_uuid0" => to_uuid, "to_uuid1" => to_uuid }.each do |label, input|
    it "test_refs_different_reference_add[#{label}]" do
      to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
      to.data.insert(properties: {}, uuid: to_uuid)

      source = collection_factory(
        name: "From",
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      from_uuid = source.data.insert(properties: {})

      source.data.reference_add(from_property: "ref", from_uuid: from_uuid, to: input)

      obj = source.query.fetch_object_by_id(from_uuid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid)
    end
  end

  ref_inputs.each do |label, input|
    it "test_refs_different_reference_add_many[#{label}]" do
      to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
      to.data.insert(properties: {}, uuid: to_uuid)
      to.data.insert(properties: {}, uuid: to_uuid2)

      source = collection_factory(
        name: "From",
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      from_uuid = source.data.insert(properties: {})

      source.data.reference_add_many(
        [data::DataReference.new(from_property: "ref", from_uuid: from_uuid, to_uuid: input)]
      )

      obj = source.query.fetch_object_by_id(from_uuid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid)
    end
  end

  { "to_uuid0" => to_uuid2, "to_uuid1" => to_uuid2, "to_uuid2" => [to_uuid2],
    "to_uuid3" => [to_uuid2] }.each do |label, input|
    it "test_refs_different_reference_replace[#{label}]" do
      to = collection_factory(name: "To", vectorizer_config: config::Configure::Vectorizer.none)
      to.data.insert(properties: {}, uuid: to_uuid)
      to.data.insert(properties: {}, uuid: to_uuid2)

      source = collection_factory(
        name: "From",
        references: [config::ReferenceProperty.new(name: "ref", target_collection: to.name)],
        vectorizer_config: config::Configure::Vectorizer.none
      )

      from_uuid = source.data.insert(properties: {})
      source.data.reference_add(from_property: "ref", from_uuid: from_uuid, to: to_uuid)
      obj = source.query.fetch_object_by_id(from_uuid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid)

      source.data.reference_replace(from_property: "ref", from_uuid: from_uuid, to: input)
      obj = source.query.fetch_object_by_id(from_uuid, return_references: [query::QueryReference.new(link_on: "ref")])
      expect(obj.references["ref"].objects[0].uuid).to eq(to_uuid2)
    end
  end

  # Python passes TypedDict classes that are not reference models; the Ruby equivalent of an
  # invalid "generic" is any value that is not a QueryReference (or a list of them).
  it "test_bad_generic_return_references" do
    collection = collection_factory(
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
    )

    some_generic = { "field" => Integer }

    uuid = collection.data.insert(properties: { "Name" => "A" })
    expect do
      collection.query.fetch_object_by_id(uuid, return_references: some_generic)
    end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)

    expect do
      collection.query.fetch_object_by_id(uuid, return_references: some_generic)
    end.to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  # data_model_refs=Dict[str, CrossReference[Dict[str, str], None]] is a non-TypedDict generic hint
  # that Python ignores; Ruby has no data models so the collection is created without it.
  it "test_generic_type_hint_return_references" do
    collection = collection_factory(
      properties: [config::Property.new(name: "Name", data_type: config::DataType::TEXT)]
    )
    collection.config.add_reference(config::ReferenceProperty.new(name: "self", target_collection: collection.name))

    uuid1 = collection.data.insert(properties: { "Name" => "A" })
    uuid2 = collection.data.insert(properties: { "Name" => "B" }, references: { "self" => uuid1 })
    obj = collection.query.fetch_object_by_id(uuid2, return_references: query::QueryReference.new(link_on: "self"))
    expect(obj.properties).to eq({ "name" => "B" })
    expect(obj.references["self"].objects[0].uuid).to eq(uuid1)
    expect(obj.references["self"].objects[0].properties).to eq({ "name" => "A" })
  end
end
