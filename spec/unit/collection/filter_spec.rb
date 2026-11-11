# frozen_string_literal: true

# Port of test/collection/test_filter.py
RSpec.describe Weaviate::Classes::Query::Filter do
  let(:q) { Weaviate::Classes::Query }
  let(:invalid) { Weaviate::Exceptions::WeaviateInvalidInputError }

  it "test_empty_input_contains_any" do
    expect { q::Filter.by_id.contains_any([]) }.to raise_error(invalid)
    expect { q::Filter.by_property("test").contains_any([]) }.to raise_error(invalid)
    expect { q::Filter.by_creation_time.contains_any([]) }.to raise_error(invalid)
    expect { q::Filter.by_update_time.contains_any([]) }.to raise_error(invalid)
  end

  it "test_empty_input_contains_none_time" do
    expect { q::Filter.by_creation_time.contains_none([]) }.to raise_error(invalid)
    expect { q::Filter.by_update_time.contains_none([]) }.to raise_error(invalid)
  end

  it "test_empty_input_contains_all" do
    expect { q::Filter.by_property("test").contains_all([]) }.to raise_error(invalid)
  end

  %i[equal not_equal less_than less_or_equal greater_than greater_or_equal].each do |meth|
    it "test_empty_list_#{meth}" do
      expect { q::Filter.by_property("test").public_send(meth, []) }.to raise_error(invalid)
    end
  end

  it "test_empty_list_grpc_conversion" do
    fv = q::FilterValue.new(target: "test", value: [], operator: q::Operator::EQUAL)
    expect { Weaviate::Collections::Grpc::FilterToGRPC.convert(fv) }.to raise_error(invalid)
  end

  it "test_filter_lists" do
    f1 = q::Filter.by_property("test").equal("test")
    f2 = q::Filter.by_creation_time.greater_or_equal(Time.now)

    and_list = q::Filter.all_of([f1, f2])
    and_direct = f1 & f2
    expect(and_list).to be_a(q::FilterAnd)
    expect(and_direct).to be_a(q::FilterAnd)
    expect(and_list.filters).to eq(and_direct.filters)

    or_list = q::Filter.any_of([f1, f2])
    or_direct = f1 | f2
    expect(or_list).to be_a(q::FilterOr)
    expect(or_direct).to be_a(q::FilterOr)
    expect(or_list.filters).to eq(or_direct.filters)
  end

  it "test_filter_lists_one_entry" do
    f1 = q::Filter.by_property("test").equal("test")
    expect(q::Filter.all_of([f1])).to eq(f1)
    expect(q::Filter.any_of([f1])).to eq(f1)
  end

  it "test_filter_lists_empty" do
    expect { q::Filter.all_of([]) }.to raise_error(invalid)
    expect { q::Filter.any_of([]) }.to raise_error(invalid)
  end

  it "test_filter_bitwise_and_assignment" do
    f1 = q::Filter.by_property("test").equal("test")
    f2 = q::Filter.by_creation_time.greater_or_equal(Time.now)
    f3 = q::Filter.by_update_time.less_or_equal(Time.now)

    f4 = f1 & f2
    f4 &= f3
    and_direct = q::Filter.all_of([f1, f2]) & f3
    expect(f4).to be_a(q::FilterAnd)
    expect(and_direct).to be_a(q::FilterAnd)
    expect(f4.filters[0]).to be_a(q::FilterAnd)
    expect(and_direct.filters[0]).to be_a(q::FilterAnd)
    expect(f4.filters[0].filters).to eq(and_direct.filters[0].filters)
    expect(f4.filters[1]).to eq(f3)
  end

  it "test_filter_bitwise_or_assignment" do
    f1 = q::Filter.by_property("test").equal("test")
    f2 = q::Filter.by_creation_time.greater_or_equal(Time.now)
    f3 = q::Filter.by_update_time.less_or_equal(Time.now)

    f4 = f1 | f2
    f4 |= f3
    or_direct = q::Filter.any_of([f1, f2]) | f3
    expect(f4).to be_a(q::FilterOr)
    expect(or_direct).to be_a(q::FilterOr)
    expect(f4.filters[0]).to be_a(q::FilterOr)
    expect(or_direct.filters[0]).to be_a(q::FilterOr)
    expect(f4.filters[0].filters).to eq(or_direct.filters[0].filters)
    expect(f4.filters[1]).to eq(f3)
  end

  it "test_filter_bitwise_invert_assignment" do
    f1 = q::Filter.by_property("test").equal("test")
    not_f1 = q::Filter.not_(f1)
    invert_f1 = ~f1

    expect(invert_f1).to be_a(q::FilterNot)
    expect(not_f1).to be_a(q::FilterNot)
    expect(invert_f1.filters.length).to eq(1)
    expect(invert_f1.filters).to eq(not_f1.filters)
  end

  it "test_auto_capitalize_first_letter_by_ref_multi_target" do
    result = q::Filter.by_ref_multi_target("ref1", target_collection: "test")
    expect(result.instance_variable_get(:@target).target_collection).to eq("Test")
  end

  it "test_reuse_by_ref_builder_for_independent_filters" do
    ref = q::Filter.by_ref("hasCategory")

    name_filter = ref.by_property("name").equal("Electronics")
    rating_filter = ref.by_property("rating").greater_than(4)

    expect(name_filter.target.link_on).to eq("hasCategory")
    expect(name_filter.target.target).to eq("name")
    expect(rating_filter.target.link_on).to eq("hasCategory")
    expect(rating_filter.target.target).to eq("rating")
    expect(name_filter.target).not_to equal(rating_filter.target)

    property_filter = ref.by_property("name")
    first_value = property_filter.equal("Electronics")
    second_value = property_filter.equal("Appliances")

    expect(first_value.target.link_on).to eq("hasCategory")
    expect(first_value.target.target).to eq("name")
    expect(second_value.target.link_on).to eq("hasCategory")
    expect(second_value.target.target).to eq("name")
    expect(first_value.target).not_to equal(second_value.target)
  end

  {
    "EQUAL" => :OPERATOR_EQUAL, "NOT_EQUAL" => :OPERATOR_NOT_EQUAL, "LESS_THAN" => :OPERATOR_LESS_THAN,
    "LESS_THAN_EQUAL" => :OPERATOR_LESS_THAN_EQUAL, "GREATER_THAN" => :OPERATOR_GREATER_THAN,
    "GREATER_THAN_EQUAL" => :OPERATOR_GREATER_THAN_EQUAL, "LIKE" => :OPERATOR_LIKE, "IS_NULL" => :OPERATOR_IS_NULL,
    "CONTAINS_ANY" => :OPERATOR_CONTAINS_ANY, "CONTAINS_ALL" => :OPERATOR_CONTAINS_ALL,
    "CONTAINS_NONE" => :OPERATOR_CONTAINS_NONE, "WITHIN_GEO_RANGE" => :OPERATOR_WITHIN_GEO_RANGE,
    "AND" => :OPERATOR_AND, "OR" => :OPERATOR_OR, "NOT" => :OPERATOR_NOT
  }.each do |operator, want|
    it "test_operator_to_grpc[#{operator}]" do
      op = Weaviate::Classes::Query::Operator.const_get(operator)
      expect(Weaviate::Classes::Query::Operator.to_grpc(op)).to eq(want)
      # the protobuf enum must exist
      expect(Weaviate::V1::Filters::Operator.resolve(want)).not_to be_nil
    end
  end

  describe "gRPC conversion of values and targets" do
    let(:conv) { Weaviate::Collections::Grpc::FilterToGRPC }

    it "converts scalar and list values to the right protobuf fields" do
      expect(conv.convert(q::Filter.by_property("b").equal(true)).value_boolean).to be(true)
      expect(conv.convert(q::Filter.by_property("i").equal(3)).value_int).to eq(3)
      expect(conv.convert(q::Filter.by_property("n").equal(1.5)).value_number).to eq(1.5)
      expect(conv.convert(q::Filter.by_property("t").like("a*")).value_text).to eq("a*")
      expect(conv.convert(q::Filter.by_property("t").contains_any(%w[a b])).value_text_array.values.to_a).to eq(%w[a b])
      expect(conv.convert(q::Filter.by_property("i").contains_all([1, 2])).value_int_array.values.to_a).to eq([1, 2])
      expect(conv.convert(q::Filter.by_property("n").contains_none([1.5])).value_number_array.values.to_a).to eq([1.5])
      expect(conv.convert(q::Filter.by_property("b").contains_any([true])).value_boolean_array.values.to_a).to eq([true])

      date = Time.utc(2024, 1, 2, 3, 4, 5)
      expect(conv.convert(q::Filter.by_creation_time.equal(date)).value_text)
        .to eq(Weaviate::Util.datetime_to_string(date))
    end

    it "converts geo ranges, reference counts and reference chains" do
      geo = Struct.new(:latitude, :longitude).new(1.0, 2.0)
      grpc = conv.convert(q::Filter.by_property("loc").within_geo_range(geo, distance: 3.0))
      expect([grpc.value_geo.latitude, grpc.value_geo.longitude, grpc.value_geo.distance]).to eq([1.0, 2.0, 3.0])

      expect(conv.convert(q::Filter.by_ref_count("ref").equal(2)).target.count.on).to eq("ref")

      chained = q::Filter.by_ref("a").by_ref_multi_target("b", target_collection: "other").by_property("p", length: true).equal(1)
      target = conv.convert(chained).target
      expect(target.single_target.on).to eq("a")
      expect(target.single_target.target.multi_target.on).to eq("b")
      expect(target.single_target.target.multi_target.target_collection).to eq("Other")
      expect(target.single_target.target.multi_target.target.property).to eq("len(p)")
    end

    it "converts to the REST where shape" do
      f = q::Filter.by_ref_multi_target("ref", target_collection: "Other").by_property("p").equal("x") | q::Filter.by_property("n").equal(1)
      expect(Weaviate::Collections::Grpc::FilterToREST.convert(f)).to eq(
        "operator" => "Or",
        "operands" => [
          { "operator" => "Equal", "path" => %w[ref Other p], "valueText" => "x" },
          { "operator" => "Equal", "path" => ["n"], "valueInt" => 1 }
        ]
      )
    end
  end
end
