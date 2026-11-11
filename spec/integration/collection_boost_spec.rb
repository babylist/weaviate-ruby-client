# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_boost.py
RSpec.describe "collection boost", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:boost) { Weaviate::Classes::Query::Boost }
  let(:filter) { Weaviate::Classes::Query::Filter }
  let(:metadata_query) { Weaviate::Classes::Query::MetadataQuery }

  # Create a collection with numeric and date properties for boost testing.
  def create_collection
    dt = cfg::DataType
    collection = collection_factory(
      properties: [
        cfg::Property.new(name: "text", data_type: dt::TEXT),
        cfg::Property.new(name: "price", data_type: dt::NUMBER),
        cfg::Property.new(name: "rating", data_type: dt::NUMBER),
        cfg::Property.new(name: "count", data_type: dt::INT),
        cfg::Property.new(name: "created", data_type: dt::DATE)
      ],
      vectorizer_config: cfg::Configure::Vectorizer.none,
      vector_index_config: cfg::Configure::VectorIndex.flat
    )
    skip("Boost requires Weaviate >= 1.38.0") if server_version.is_lower_than(1, 38, 0)
    data_object = Weaviate::Classes::Data::DataObject
    rows = [
      ["cheap good", 10.0, 4.9, 1000, "2024-01-01T00:00:00Z", [1.0, 0.0, 0.0]],
      ["cheap bad", 10.0, 2.0, 5, "2020-01-01T00:00:00Z", [0.9, 0.1, 0.0]],
      ["expensive good", 500.0, 4.8, 500, "2023-06-01T00:00:00Z", [0.0, 1.0, 0.0]],
      ["expensive bad", 500.0, 1.5, 2, "2019-01-01T00:00:00Z", [0.0, 0.9, 0.1]],
      ["mid range", 50.0, 3.5, 100, "2022-01-01T00:00:00Z", [0.0, 0.0, 1.0]]
    ]
    collection.data.insert_many(
      rows.map do |text, price, rating, count, created, vector|
        data_object.new(
          properties: { "text" => text, "price" => price, "rating" => rating, "count" => count, "created" => created },
          vector: vector
        )
      end
    )
    collection
  end

  def boosted_near_vector(collection, boost_)
    collection.query.near_vector([1.0, 0.0, 0.0], limit: 5, boost: boost_,
                                                  return_metadata: metadata_query.new(distance: true)).objects
  end

  it "test_boost_filter" do
    # Boost results matching a filter: boosted items should score higher.
    collection = create_collection

    baseline = collection.query.near_vector([1.0, 0.0, 0.0], limit: 5,
                                                             return_metadata: metadata_query.new(distance: true)).objects
    boosted = boosted_near_vector(collection, boost.filter(filter.by_property("rating").greater_or_equal(4.0),
                                                           weight: 1.0))

    expect(boosted.length).to eq(5)
    # The boost should change the ordering compared to baseline
    expect(baseline.map(&:uuid)).not_to eq(boosted.map(&:uuid))
  end

  it "test_boost_numeric_decay" do
    # Numeric decay: prefer items with price near the origin.
    collection = create_collection
    result = boosted_near_vector(
      collection,
      boost.numeric_decay("price", origin: 50.0, scale: 20.0, curve: boost::Curve::LINEAR, decay: 0.5, weight: 1.0)
    )
    expect(result.length).to eq(5)
  end

  it "test_boost_time_decay" do
    # Time decay: prefer items with dates closer to origin.
    collection = create_collection
    result = boosted_near_vector(
      collection,
      boost.time_decay("created", origin: "2024-01-01T00:00:00Z", scale: "365d", curve: boost::Curve::EXPONENTIAL,
                                  decay: 0.3, weight: 1.0)
    )
    expect(result.length).to eq(5)
  end

  it "test_boost_property_value" do
    # Property value boost: rank by a numeric property directly.
    collection = create_collection
    result = boosted_near_vector(collection,
                                 boost.numeric_property("count", modifier: boost::Modifier::LOG1P, weight: 1.0))
    expect(result.length).to eq(5)
  end

  it "test_boost_blend" do
    # Blend multiple boost conditions together.
    collection = create_collection
    result = boosted_near_vector(
      collection,
      boost.blend(
        [
          boost.filter(filter.by_property("rating").greater_or_equal(4.0), weight: 2.0),
          boost.numeric_decay("price", origin: 30.0, scale: 100.0, curve: boost::Curve::EXPONENTIAL)
        ],
        weight: 0.8
      )
    )
    expect(result.length).to eq(5)
  end

  it "test_boost_with_depth" do
    # Boost with explicit depth parameter.
    collection = create_collection
    result = boosted_near_vector(collection,
                                 boost.filter(filter.by_property("rating").greater_or_equal(4.0), weight: 1.0,
                                                                                                   depth: 100))
    expect(result.length).to eq(5)
  end

  it "test_boost_bm25" do
    # Boost works with BM25 keyword search.
    collection = create_collection
    result = collection.query.bm25(
      "cheap", limit: 5,
               boost: boost.filter(filter.by_property("rating").greater_or_equal(4.0), weight: 1.0),
               return_metadata: metadata_query.new(score: true)
    ).objects
    expect(result.length).to be >= 1
  end

  it "test_boost_hybrid" do
    # Boost works with hybrid search.
    collection = create_collection
    result = collection.query.hybrid(
      "cheap", vector: [1.0, 0.0, 0.0], limit: 5,
               boost: boost.filter(filter.by_property("price").less_than(100.0), weight: 0.6),
               return_metadata: metadata_query.new(score: true)
    ).objects
    expect(result.length).to be >= 1
  end

  it "test_boost_api_surface" do
    expect { boost.new }.to raise_error(TypeError)

    # Static methods produce BoostReturn (Python _Boost) instances
    b = boost.filter(filter.by_property("x").equal("y"), weight: 0.5)
    expect(b.conditions.length).to eq(1)
    expect(b.weight).to eq(0.5)

    b = boost.blend(
      [
        boost.filter(filter.by_property("x").equal("y"), weight: 1.0),
        boost.numeric_property("z", modifier: boost::Modifier::LOG1P)
      ],
      weight: 0.8, depth: 200
    )
    expect(b.conditions.length).to eq(2)
    expect(b.weight).to eq(0.8)
    expect(b.depth).to eq(200)

    # blend() also accepts a single boost
    b = boost.blend(boost.filter(filter.by_property("x").equal("y")), weight: 0.5)
    expect(b.conditions.length).to eq(1)
    expect(b.weight).to eq(0.5)
  end

  it "test_boost_blend_rejects_sub_boost_depth" do
    expect { boost.blend(boost.numeric_property("count", depth: 500), depth: 100) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  it "test_boost_default_curve_is_unspecified" do
    # Omitting curve defaults to nil (sent as UNSPECIFIED on the wire).
    b = boost.numeric_decay("price", origin: 50.0, scale: 20.0)
    expect(b.conditions[0].numeric_decay.curve).to be_nil

    b = boost.time_decay("created", scale: "7d")
    expect(b.conditions[0].time_decay.curve).to be_nil
  end

  it "test_boost_default_modifier_is_unspecified" do
    # Omitting modifier defaults to nil (sent as UNSPECIFIED on the wire).
    b = boost.numeric_property("count")
    expect(b.conditions[0].property_value.modifier).to be_nil
  end
end
