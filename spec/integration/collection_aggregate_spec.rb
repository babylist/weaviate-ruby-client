# frozen_string_literal: true

# Port of weaviate-python-client/integration/test_collection_aggregate.py
RSpec.describe "collection aggregate", :integration do
  include Batch4Helpers

  let(:cfg) { Weaviate::Classes::Config }
  let(:q) { Weaviate::Classes::Query }
  let(:agg) { Weaviate::Classes::Aggregate }
  let(:out) { Weaviate::Outputs::Aggregate }
  let(:exc) { Weaviate::Exceptions }

  uuid1 = "8ad0d33c-8db1-4437-87f3-72161ca2a51a"
  uuid2 = "577887c1-4c6b-5594-aa62-f0c17883d9cf"
  missing_param_msg = "You must provide at least one of the following arguments: certainty, distance, " \
                      "object_limit when vector searching"
  text1 = "some text"
  text2 = "nothing like the other one at all, not even a little bit"

  def text_prop(name = "text") = cfg::Property.new(name: name, data_type: cfg::DataType::TEXT)

  def contextionary_collection(**kw)
    collection_factory(
      properties: [text_prop],
      vectorizer_config: cfg::Configure::Vectorizer.text2vec_contextionary(vectorize_collection_name: false),
      **kw
    )
  end

  def top_metrics
    [agg::Metrics.new("text").text(count: true, top_occurrences_count: true, top_occurrences_value: true)]
  end

  def expect_top_occurrences(res, expected_len, text1, text2)
    expect(res.properties["text"]).to be_a(out::AggregateText)
    expect(res.properties["text"].count).to eq(expected_len)
    expect(res.properties["text"].top_occurrences.length).to eq(expected_len)
    values = res.properties["text"].top_occurrences.map(&:value)
    expect(values).to include(text1)
    if expected_len == 2
      expect(values).to include(text2)
    else
      expect(values).not_to include(text2)
    end
  end

  [1, 10_000, 20_000, 20_001, 100_000].each do |how_many|
    it "test_collection_length[#{how_many}]" do
      collection = collection_factory(vectorizer_config: cfg::Configure::Vectorizer.none)
      collection.data.insert_many(Array.new(how_many) { {} })
      expect(collection.length).to eq(how_many)
    end
  end

  [1, 10_000, 20_000, 20_001, 100_000].each do |how_many|
    it "test_collection_length_tenant[#{how_many}]" do
      collection = collection_factory(
        vectorizer_config: cfg::Configure::Vectorizer.none,
        multi_tenancy_config: cfg::Configure.multi_tenancy(enabled: true)
      )
      tenant = Weaviate::Classes::Tenants::Tenant
      collection.tenants.create([tenant.new(name: "tenant1"), tenant.new(name: "tenant2"), tenant.new(name: "tenant3")])
      collection.with_tenant("tenant2").data.insert_many(Array.new(how_many * 2) { {} })

      expect(collection.with_tenant("tenant2").length).to eq(how_many * 2)
      expect(collection.with_tenant("tenant3").length).to eq(0)
    end
  end

  it "test_empty_aggregation" do
    collection = collection_factory(properties: [text_prop])
    res = collection.aggregate.over_all
    expect(res.total_count).to eq(0)
  end

  it "test_simple_aggregation" do
    collection = collection_factory(properties: [text_prop])
    collection.data.insert({ "text" => "some text" })
    res = collection.aggregate.over_all(return_metrics: [agg::Metrics.new("text").text(count: true)])
    expect(res.properties["text"]).to be_a(out::AggregateText)
    expect(res.properties["text"].count).to eq(1)
  end

  it "test_aggregation_top_occurence_with_limit" do
    collection = collection_factory(properties: [text_prop])
    collection.data.insert({ "text" => "one" })
    collection.data.insert({ "text" => "one" })
    collection.data.insert({ "text" => "two" })

    # Test deprecated min_occurrences parameter triggers warning
    res_old, warnings = Weaviate::Warnings.capture do
      collection.aggregate.over_all(return_metrics: [agg::Metrics.new("text").text(min_occurrences: 1)])
    end
    expect(warnings.length).to eq(1)
    expect(warnings[0]).to include("Dep028")
    expect(warnings[0]).to include("min_occurrences")
    expect(warnings[0]).to include("limit")

    # Test new limit parameter
    res = collection.aggregate.over_all(return_metrics: [agg::Metrics.new("text").text(limit: 1)])

    # Verify both approaches produce the same result
    expect(res.properties["text"]).to eq(res_old.properties["text"])

    expect(res.properties["text"]).to be_a(out::AggregateText)
    expect(res.properties["text"].top_occurrences.length).to eq(1)
    expect(res.properties["text"].top_occurrences[0].count).to eq(2)
  end

  it "test_aggregation_groupby_with_limit" do
    collection = collection_factory(properties: [text_prop])
    collection.data.insert({ "text" => "one" })
    collection.data.insert({ "text" => "two" })
    collection.data.insert({ "text" => "three" })
    res = collection.aggregate.over_all(
      return_metrics: [agg::Metrics.new("text").text(count: true)],
      group_by: agg::GroupByAggregate.new(prop: "text", limit: 2)
    )
    expect(res.groups.length).to eq(2)
    expect(res.groups[0].properties["text"].count).to eq(1)
    expect(res.groups[1].properties["text"].count).to eq(1)
  end

  it "test_aggregation_groupby_no_results" do
    collection = collection_factory(properties: [text_prop])
    res = collection.aggregate.over_all(
      return_metrics: [agg::Metrics.new("text").text(count: true)],
      group_by: agg::GroupByAggregate.new(prop: "text", limit: 2)
    )
    expect(res.groups.length).to eq(0)
  end

  filter = Weaviate::Classes::Query::Filter
  date2 = Time.utc(2021, 1, 2, 0, 0, 0)
  {
    "text" => -> { filter.by_property("text").equal("two") },
    "int" => -> { filter.by_property("int").equal(2) },
    "float" => -> { filter.by_property("float").equal(2.0) },
    "bool" => -> { filter.by_property("bool").equal(false) },
    "date" => -> { filter.by_property("date").equal(date2) },
    "text_or_int" => -> { filter.by_property("text").equal("two") | filter.by_property("int").equal(2) },
    "uuid" => -> { filter.by_property("uuid").equal(uuid2) },
    "texts" => -> { filter.by_property("texts").contains_any(["two"]) },
    "ints" => -> { filter.by_property("ints").contains_any([2]) },
    "floats" => -> { filter.by_property("floats").contains_any([2.0]) },
    "bools" => -> { filter.by_property("bools").contains_any([false]) },
    "dates" => -> { filter.by_property("dates").contains_any([date2]) },
    "uuids" => -> { filter.by_property("uuids").contains_any([uuid2]) }
  }.each do |label, filter_|
    it "test_over_all_with_filters[#{label}]" do
      dt = cfg::DataType
      collection = collection_factory(
        properties: [
          cfg::Property.new(name: "text", data_type: dt::TEXT),
          cfg::Property.new(name: "int", data_type: dt::INT),
          cfg::Property.new(name: "float", data_type: dt::NUMBER),
          cfg::Property.new(name: "bool", data_type: dt::BOOL),
          cfg::Property.new(name: "date", data_type: dt::DATE),
          cfg::Property.new(name: "uuid", data_type: dt::UUID),
          cfg::Property.new(name: "texts", data_type: dt::TEXT_ARRAY),
          cfg::Property.new(name: "ints", data_type: dt::INT_ARRAY),
          cfg::Property.new(name: "floats", data_type: dt::NUMBER_ARRAY),
          cfg::Property.new(name: "bools", data_type: dt::BOOL_ARRAY),
          cfg::Property.new(name: "dates", data_type: dt::DATE_ARRAY),
          cfg::Property.new(name: "uuids", data_type: dt::UUID_ARRAY)
        ]
      )
      collection.data.insert(
        {
          "text" => "one", "int" => 1, "float" => 1.0, "bool" => true, "date" => "2021-01-01T00:00:00Z",
          "uuid" => uuid1, "texts" => ["one"], "ints" => [1], "floats" => [1.0], "bools" => [true],
          "dates" => ["2021-01-01T00:00:00Z"], "uuids" => [uuid1]
        }
      )
      collection.data.insert(
        {
          "text" => "two", "int" => 2, "float" => 2.0, "bool" => false, "date" => "2021-01-02T00:00:00Z",
          "uuid" => uuid2, "texts" => ["two"], "ints" => [2], "floats" => [2.0], "bools" => [false],
          "dates" => ["2021-01-02T00:00:00Z"], "uuids" => [uuid2]
        }
      )

      res = collection.aggregate.over_all(
        filters: filter_.call,
        return_metrics: [agg::Metrics.new("text").text(count: true, top_occurrences_value: true)]
      )
      expect(res.properties["text"]).to be_a(out::AggregateText)
      expect(res.properties["text"].count).to eq(1)
      expect(res.properties["text"].top_occurrences[0].value).to eq("two")
    end
  end

  it "test_over_all_with_filters_ref" do
    collection = collection_factory(properties: [text_prop])
    collection.config.add_reference(cfg::ReferenceProperty.new(name: "ref", target_collection: collection.name))

    uuid_one = collection.data.insert({ "text" => "one" })
    collection.data.insert({ "text" => "two" }, references: { "ref" => uuid_one })

    metrics = [agg::Metrics.new("text").text(count: true, top_occurrences_value: true)]
    res = collection.aggregate.over_all(
      filters: q::Filter.by_ref_multi_target("ref", target_collection: collection.name).by_property("text").equal("one"),
      return_metrics: metrics
    )
    expect(res.properties["text"]).to be_a(out::AggregateText)
    expect(res.properties["text"].count).to eq(1)
    expect(res.properties["text"].top_occurrences[0].value).to eq("two")

    query = lambda do
      collection.aggregate.over_all(filters: q::Filter.by_ref("ref").by_property("text").equal("one"),
                                    return_metrics: metrics)
    end
    if server_version.is_lower_than(1, 29, 0)
      expect { query.call }.to raise_error(exc::WeaviateInvalidInputError)
    else
      res = query.call
      expect(res.properties["text"]).to be_a(out::AggregateText)
      expect(res.properties["text"].count).to eq(1)
      expect(res.properties["text"].top_occurrences[0].value).to eq("two")
    end
  end

  it "test_wrong_aggregation" do
    collection = collection_factory(properties: [text_prop])
    skip("GQL is only used for versions 1.28.4 and lower") if server_version.is_at_least(1, 29, 0)
    expect { collection.aggregate.over_all(total_count: false) }.to raise_error(exc::WeaviateQueryError) { |e|
      expect(e.message).to eq(
        "The query that you sent had no body so GraphQL was unable to parse it. You must provide at least one " \
        "option to the aggregation method in order to build a valid query."
      )
    }
  end

  near_options = [
    [{ object_limit: 1 }, 1], [{ certainty: 0.9 }, 1], [{ distance: 0.1 }, 1],
    [{ object_limit: 2 }, 2], [{ certainty: 0.1 }, 2], [{ distance: 0.9 }, 2]
  ]

  near_options.each do |option, expected_len|
    it "test_near_object_aggregation[#{option}-#{expected_len}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      uuid = collection.data.insert({ "text" => text1 })
      collection.data.insert({ "text" => text2 })
      res = collection.aggregate.near_object(uuid, return_metrics: top_metrics, **option)
      expect_top_occurrences(res, expected_len, text1, text2)
    end
  end

  it "test_near_object_missing_param" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    uuid = collection.data.insert({ "text" => text1 })
    collection.data.insert({ "text" => text2 })
    expect { collection.aggregate.near_object(uuid, return_metrics: top_metrics) }
      .to raise_error(exc::WeaviateInvalidInputError) { |e| expect(e.message).to eq(missing_param_msg) }
  end

  [[{ object_limit: 1 }, 1], [{ object_limit: 2 }, 2]].each do |option, expected_len|
    it "test_hybrid_aggregation[#{option}-#{expected_len}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      uuid = collection.data.insert({ "text" => text1 })
      obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
      expect(obj.vector).to have_key("default")
      collection.data.insert({ "text" => text2 })
      res = collection.aggregate.hybrid(nil, alpha: 1, vector: obj.vector["default"], return_metrics: top_metrics,
                                             **option)
      expect_top_occurrences(res, expected_len, text1, text2)
    end
  end

  group_bys = { "text" => -> { "text" }, "GroupByAggregate" => -> { agg::GroupByAggregate.new(prop: "text", limit: 1) } }

  group_bys.each do |label, group_by|
    it "test_hybrid_aggregation_group_by[#{label}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      collection.data.insert({ "text" => text1 })
      collection.data.insert({ "text" => text2 })

      querier = lambda do
        collection.aggregate.hybrid("text", alpha: 0, query_properties: ["text"], group_by: instance_exec(&group_by),
                                            total_count: true, object_limit: 2) # object_limit has no effect (alpha=0)
      end
      if server_version.is_lower_than(1, 25, 0)
        expect { querier.call }.to raise_error(exc::WeaviateUnsupportedFeatureError)
        next
      end

      res = querier.call
      expect(res.groups[0].grouped_by.prop).to eq("text")
      expect(res.groups[0].grouped_by.value).to eq("some text")
      expect(res.groups[0].total_count).to eq(1)
    end
  end

  group_bys.each do |label, group_by|
    it "test_hybrid_aggregation_group_by_with_named_vectors[#{label}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = collection_factory(
        properties: [text_prop],
        vectorizer_config: [cfg::Configure::NamedVectors.text2vec_contextionary(name: "all",
                                                                                vectorize_collection_name: false)]
      )
      collection.data.insert({ "text" => text1 })
      collection.data.insert({ "text" => text2 })

      querier = lambda do
        collection.aggregate.hybrid("text", alpha: 0, query_properties: ["text"], group_by: instance_exec(&group_by),
                                            total_count: true, object_limit: 2, target_vector: "all")
      end
      if server_version.is_lower_than(1, 25, 0)
        expect { querier.call }.to raise_error(exc::WeaviateUnsupportedFeatureError)
        next
      end

      res = querier.call
      expect(res.groups[0].grouped_by.prop).to eq("text")
      expect(res.groups[0].grouped_by.value).to eq("some text")
      expect(res.groups[0].total_count).to eq(1)
    end
  end

  near_options.each do |option, expected_len|
    it "test_near_vector_aggregation[#{option}-#{expected_len}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      uuid = collection.data.insert({ "text" => text1 })
      obj = collection.query.fetch_object_by_id(uuid, include_vector: true)
      expect(obj.vector).to have_key("default")
      collection.data.insert({ "text" => text2 })
      res = collection.aggregate.near_vector(obj.vector["default"], return_metrics: top_metrics, **option)
      expect_top_occurrences(res, expected_len, text1, text2)
    end
  end

  it "test_near_vector_missing_param" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    uuid_ = collection.data.insert({ "text" => "some text" })
    obj = collection.query.fetch_object_by_id(uuid_, include_vector: true)
    expect(obj.vector).to have_key("default")
    expect { collection.aggregate.near_vector(obj.vector["default"], return_metrics: top_metrics) }
      .to raise_error(exc::WeaviateInvalidInputError) { |e| expect(e.message).to eq(missing_param_msg) }
  end

  move = Weaviate::Classes::Query::Move
  (near_options + [
    [{ move_away: -> { move.new(concepts: "something", force: 0.000001) }, distance: 0.9 }, 2],
    [{ move_away: -> { move.new(objects: uuid1, force: 0.000001) }, distance: 0.9 }, 2],
    [{ move_away: -> { move.new(concepts: %w[something else], force: 0.000001) }, distance: 0.9 }, 2],
    [{ move_to: -> { move.new(objects: [uuid1, uuid2], force: 0.000001) }, distance: 0.9 }, 2]
  ]).each_with_index do |(option, expected_len), idx|
    it "test_near_text_aggregation[#{idx}-#{expected_len}]" do
      skip_if_native!("requires text2vec-contextionary")
      collection = contextionary_collection
      collection.data.insert({ "text" => text1 }, uuid: uuid1)
      collection.data.insert({ "text" => text2 }, uuid: uuid2)
      opts = option.transform_values { |v| v.is_a?(Proc) ? v.call : v }
      res = collection.aggregate.near_text(text1, return_metrics: top_metrics, **opts)
      expect_top_occurrences(res, expected_len, text1, text2)
    end
  end

  it "test_near_text_missing_param" do
    skip_if_native!("requires text2vec-contextionary")
    collection = contextionary_collection
    collection.data.insert({ "text" => text1 })
    expect { collection.aggregate.near_text(text1, return_metrics: top_metrics) }
      .to raise_error(exc::WeaviateInvalidInputError) { |e| expect(e.message).to eq(missing_param_msg) }
  end

  [{ object_limit: 1 }, { certainty: 0.9 }, { distance: 0.1 }].each do |option|
    it "test_near_image_aggregation[#{option}]" do
      skip("img2vec-neural removed from CI. This test should go in the e2e-tests repo instead")
    end
  end

  it "test_near_image_missing_param" do
    skip("img2vec-neural removed from CI. This test should go in the e2e-tests repo instead")
  end

  it "test_group_by_aggregation_argument" do
    collection = collection_factory(
      properties: [text_prop, cfg::Property.new(name: "int", data_type: cfg::DataType::INT)]
    )
    collection.data.insert({ "text" => "some text", "int" => 1 })
    collection.data.insert({ "text" => "some text", "int" => 2 })

    metrics = [agg::Metrics.new("text").text(count: true), agg::Metrics.new("int").integer(count: true)]
    res = collection.aggregate.over_all(group_by: "text", return_metrics: metrics)
    groups = res.groups
    expect(groups.length).to eq(1)
    expect(groups[0].grouped_by.prop).to eq("text")
    expect(groups[0].grouped_by.value).to eq("some text")
    expect(groups[0].properties["text"]).to be_a(out::AggregateText)
    expect(groups[0].properties["text"].count).to eq(2)
    expect(groups[0].properties["int"]).to be_a(out::AggregateInteger)
    expect(groups[0].properties["int"].count).to eq(2)

    res = collection.aggregate.over_all(group_by: "int", return_metrics: metrics)
    groups = res.groups
    expect(groups.length).to eq(2)
    old = server_version.is_lower_than(1, 29, 0)
    one = old ? "1" : 1
    two = old ? "2" : 2
    expect(groups[0].grouped_by.prop).to eq("int")
    expect(groups[0].grouped_by.value == one || groups[1].grouped_by.value == one).to be(true)
    expect(groups[0].properties["text"]).to be_a(out::AggregateText)
    expect(groups[0].properties["text"].count).to eq(1)
    expect(groups[0].properties["int"]).to be_a(out::AggregateInteger)
    expect(groups[0].properties["int"].count).to eq(1)
    expect(groups[1].grouped_by.prop).to eq("int")
    expect(groups[1].grouped_by.value == two || groups[0].grouped_by.value == two).to be(true)
    expect(groups[1].properties["text"]).to be_a(out::AggregateText)
    expect(groups[1].properties["text"].count).to eq(1)
    expect(groups[1].properties["int"]).to be_a(out::AggregateInteger)
    expect(groups[1].properties["int"].count).to eq(1)
  end

  it "test_mistake_in_usage" do
    skip("Validation logic is not robust enough currently")
  end

  it "test_all_available_aggregations" do
    dt = cfg::DataType
    collection = collection_factory(
      properties: [
        cfg::Property.new(name: "text", data_type: dt::TEXT),
        cfg::Property.new(name: "texts", data_type: dt::TEXT_ARRAY),
        cfg::Property.new(name: "int", data_type: dt::INT),
        cfg::Property.new(name: "ints", data_type: dt::INT_ARRAY),
        cfg::Property.new(name: "float", data_type: dt::NUMBER),
        cfg::Property.new(name: "floats", data_type: dt::NUMBER_ARRAY),
        cfg::Property.new(name: "bool", data_type: dt::BOOL),
        cfg::Property.new(name: "bools", data_type: dt::BOOL_ARRAY),
        cfg::Property.new(name: "date", data_type: dt::DATE),
        cfg::Property.new(name: "dates", data_type: dt::DATE_ARRAY)
      ]
    )
    collection.config.add_reference(cfg::ReferenceProperty.new(name: "ref", target_collection: collection.name))
    collection.data.insert(
      {
        "text" => "some text", "texts" => ["some text", "some text"], "int" => 1, "ints" => [1, 2],
        "float" => 1.0, "floats" => [1.0, 2.0], "bool" => true, "bools" => [true, false],
        "date" => "2021-01-01T00:00:00Z", "dates" => ["2021-01-01T00:00:00Z", "2021-01-02T00:00:00Z"]
      }
    )
    m = agg::Metrics
    res = collection.aggregate.over_all(
      return_metrics: [
        m.new("text").text, m.new("texts").text, m.new("int").integer, m.new("ints").integer,
        m.new("float").number, m.new("floats").number, m.new("bool").boolean, m.new("bools").boolean,
        m.new("date").date_, m.new("dates").date_
      ]
    )

    text = res.properties["text"]
    expect(text).to be_a(out::AggregateText)
    expect(text.count).to eq(1)
    expect(text.top_occurrences[0].count).to eq(1)
    expect(text.top_occurrences[0].value).to eq("some text")

    texts = res.properties["texts"]
    expect(texts).to be_a(out::AggregateText)
    expect(texts.count).to eq(2)
    expect(texts.top_occurrences[0].count).to eq(2)
    expect(texts.top_occurrences[0].value).to eq("some text")

    int_ = res.properties["int"]
    expect(int_).to be_a(out::AggregateInteger)
    expect([int_.count, int_.maximum, int_.mean, int_.median, int_.minimum, int_.mode, int_.sum_]).to eq([1] * 7)

    ints = res.properties["ints"]
    expect(ints).to be_a(out::AggregateInteger)
    expect(ints.count).to eq(2)
    expect(ints.maximum).to eq(2)
    expect(ints.mean).to eq(1.5)
    expect(ints.median).to eq(1.5)
    expect(ints.minimum).to eq(1)
    expect(ints.mode).to eq(1)

    float_ = res.properties["float"]
    expect(float_).to be_a(out::AggregateNumber)
    expect(float_.count).to eq(1)
    expect([float_.maximum, float_.mean, float_.median, float_.minimum, float_.mode]).to eq([1.0] * 5)

    floats = res.properties["floats"]
    expect(floats).to be_a(out::AggregateNumber)
    expect(floats.count).to eq(2)
    expect(floats.maximum).to eq(2.0)
    expect(floats.mean).to eq(1.5)
    expect(floats.median).to eq(1.5)
    expect(floats.minimum).to eq(1.0)
    expect(floats.mode).to eq(1.0)

    bool_ = res.properties["bool"]
    expect(bool_).to be_a(out::AggregateBoolean)
    expect(bool_.count).to eq(1)
    expect(bool_.percentage_false).to eq(0)
    expect(bool_.percentage_true).to eq(1)
    expect(bool_.total_false).to eq(0)
    expect(bool_.total_true).to eq(1)

    bools = res.properties["bools"]
    expect(bools).to be_a(out::AggregateBoolean)
    expect(bools.count).to eq(2)
    expect(bools.percentage_false).to eq(0.5)
    expect(bools.percentage_true).to eq(0.5)
    expect(bools.total_false).to eq(1)
    expect(bools.total_true).to eq(1)

    date = res.properties["date"]
    expect(date).to be_a(out::AggregateDate)
    expect(date.count).to eq(1)
    expect(date.maximum).to eq("2021-01-01T00:00:00Z")
    expect(date.median).to eq("2021-01-01T00:00:00Z")
    expect(date.minimum).to eq("2021-01-01T00:00:00Z")
    expect(date.mode).to eq("2021-01-01T00:00:00Z")

    dates = res.properties["dates"]
    expect(dates).to be_a(out::AggregateDate)
    expect(dates.count).to eq(2)
    expect(dates.maximum).to eq("2021-01-02T00:00:00Z")
    expect(dates.median).to eq("2021-01-01T12:00:00Z")
    expect(dates.minimum).to eq("2021-01-01T00:00:00Z")
    # mode is flakey: sometimes returns 01, other times 02
  end

  it "test_hybrid_bm25_operators" do
    collection = collection_factory(properties: [text_prop("name")], vectorizer_config: cfg::Configure::Vectorizer.none)
    if server_version.is_lower_than(1, 31, 0)
      skip("bm25 operators are only supported in versions higher than 1.31.0")
    end

    ["banana one", "banana two", "banana three", "banana four"].each { |n| collection.data.insert({ "name" => n }) }

    res = collection.aggregate.hybrid("banana two", alpha: 0, bm25_operator: q::BM25Operator.or_(minimum_match: 1),
                                                    object_limit: 10)
    expect(res.total_count).to eq(4)
  end

  it "test_aggregate_empty_result_none_values" do
    # Test for issue #11219: aggregate metrics should be nil for empty result sets, not 0/0.0.
    collection = collection_factory(
      properties: [
        cfg::Property.new(name: "bucket", data_type: cfg::DataType::INT, index_filterable: true,
                          index_range_filters: true),
        cfg::Property.new(name: "intVal", data_type: cfg::DataType::INT),
        cfg::Property.new(name: "numberVal", data_type: cfg::DataType::NUMBER)
      ],
      vectorizer_config: cfg::Configure::Vectorizer.none,
      inverted_index_config: cfg::Configure.inverted_index(index_null_state: true)
    )
    if server_version.is_lower_than(1, 29, 0)
      skip("gRPC aggregates are only supported in versions 1.29.0 and higher")
    end

    collection.data.insert({ "bucket" => 0, "intVal" => 123, "numberVal" => 456.78 })

    all = { count: true, maximum: true, mean: true, median: true, minimum: true, mode: true, sum_: true }
    res = collection.aggregate.over_all(
      filters: q::Filter.by_property("bucket").equal(99),
      total_count: true,
      return_metrics: [agg::Metrics.new("intVal").integer(**all), agg::Metrics.new("numberVal").number(**all)]
    )

    expect(res.total_count).to eq(0)

    int_metrics = res.properties["intVal"]
    expect(int_metrics).to be_a(out::AggregateInteger)
    expect(int_metrics.count).to eq(0)
    %i[maximum mean median minimum mode sum_].each do |field|
      expect(int_metrics.public_send(field)).to be_nil, "#{field} should be nil for empty result set"
    end

    number_metrics = res.properties["numberVal"]
    expect(number_metrics).to be_a(out::AggregateNumber)
    expect(number_metrics.count).to eq(0)
    %i[maximum mean median minimum mode sum_].each do |field|
      expect(number_metrics.public_send(field)).to be_nil, "#{field} should be nil for empty result set"
    end
  end
end
