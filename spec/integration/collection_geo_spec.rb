# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_geo.py
RSpec.describe "collection geo", :integration do
  config = Weaviate::Classes::Config
  geo = Weaviate::Classes::Data::GeoCoordinate
  filter = Weaviate::Classes::Query::Filter

  it "test_creating_geo_props" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "geo", data_type: config::DataType::GEO_COORDINATES)]
    )

    obj_uuid = collection.data.insert({ "geo" => geo.new(latitude: 1.0, longitude: 1.0) })

    obj = collection.query.fetch_object_by_id(obj_uuid)
    expect(obj).not_to be_nil
    expect(obj.properties["geo"]).to eq(geo.new(latitude: 1.0, longitude: 1.0))

    batch_ret = collection.data.insert_many([{ "geo" => geo.new(latitude: 2.0, longitude: 1.0) }])
    expect(batch_ret.has_errors).to be(false)

    obj_batch = collection.query.fetch_object_by_id(batch_ret.uuids[0])
    expect(obj_batch).not_to be_nil
    expect(obj_batch.properties["geo"]).to eq(geo.new(latitude: 2.0, longitude: 1.0))

    # also accept dicts, but don't show that in the docs
    obj_uuid2 = collection.data.insert({ "geo" => { "latitude" => 1.0, "longitude" => 3.0 } })
    obj2 = collection.query.fetch_object_by_id(obj_uuid2)
    expect(obj2).not_to be_nil
    expect(obj2.properties["geo"]).to eq(geo.new(latitude: 1.0, longitude: 3.0))

    batch_ret2 = collection.data.insert_many([{ "geo" => geo.new(latitude: 3.0, longitude: 1.0) }])
    expect(batch_ret2.has_errors).to be(false)

    obj_batch2 = collection.query.fetch_object_by_id(batch_ret2.uuids[0])
    expect(obj_batch2).not_to be_nil
    expect(obj_batch2.properties["geo"]).to eq(geo.new(latitude: 3.0, longitude: 1.0))
  end

  it "test_geo_props_query" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "geo", data_type: config::DataType::GEO_COORDINATES)]
    )

    collection.data.insert({ "geo" => geo.new(latitude: 1.0, longitude: 2.0) })

    objs = collection.query.fetch_objects
    expect(objs.objects[0].properties["geo"]).to eq(geo.new(latitude: 1.0, longitude: 2.0))
  end

  it "test_geo_props_filter" do
    collection = collection_factory(
      vectorizer_config: config::Configure::Vectorizer.none,
      properties: [config::Property.new(name: "geo", data_type: config::DataType::GEO_COORDINATES)]
    )

    uuid1 = collection.data.insert({ "geo" => geo.new(latitude: 1.0, longitude: 2.0) })
    collection.data.insert({ "geo" => geo.new(latitude: 89.0, longitude: 179.0) })
    objs = collection.query.fetch_objects(
      filters: filter.by_property("geo").within_geo_range(geo.new(latitude: 1.0, longitude: 2.01), distance: 2000.0),
      return_properties: ["geo"]
    )
    expect(objs.objects.length).to eq(1)
    expect(objs.objects[0].uuid).to eq(uuid1)
    expect(objs.objects[0].properties["geo"]).to eq(geo.new(latitude: 1.0, longitude: 2.0))
  end
end
