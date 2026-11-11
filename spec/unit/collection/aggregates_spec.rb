# frozen_string_literal: true

# Port of test/collection/test_aggregates.py
RSpec.describe Weaviate::Collections::Aggregate::AggregateCollection do
  let(:connection) do
    con = Weaviate::Connect::Connection.new(
      connection_params: Weaviate::Connect::ConnectionParams.from_url("http://localhost:8080", 50_051)
    )
    con.instance_variable_set(:@connected, true)
    con
  end

  let(:aggregate) do
    described_class.new(connection: connection, name: "dummy", consistency_level: nil, tenant: nil,
                        validate_arguments: false)
  end

  def expect_invalid(&block)
    expect(&block).to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  it "test_bad_aggregate_inputs" do
    # over_all
    expect_invalid { aggregate.over_all(filters: "wrong") }
    expect_invalid { aggregate.over_all(group_by: 42) }
    expect_invalid { aggregate.over_all(total_count: "wrong") }
    expect_invalid { aggregate.over_all(return_metrics: "wrong") }
    # near text
    expect_invalid { aggregate.near_text(42) }
    expect_invalid { aggregate.near_text("hi", certainty: "wrong") }
    expect_invalid { aggregate.near_text("hi", distance: "wrong") }
    expect_invalid { aggregate.near_text("hi", move_to: "wrong") }
    expect_invalid { aggregate.near_text("hi", move_away: "wrong") }
    expect_invalid { aggregate.near_text("hi", object_limit: "wrong") }
    # near object
    expect_invalid { aggregate.near_object(42) }
    # near vector
    expect_invalid { aggregate.near_vector(42) }
    # near image
    expect_invalid { aggregate.near_image(42) }
  end
end

RSpec.describe Weaviate::Collections::Aggregate::GQLBuilder do
  Metrics = Weaviate::Classes::Aggregate::Metrics

  it "builds the same GraphQL as the Python AggregateBuilder" do
    q = described_class.new("thing")
                       .with_fields(Metrics.new("count").integer(mean: true).to_gql)
                       .with_where({ "path" => ["name"], "operator" => "Equal", "valueText" => "a\"b" })
                       .with_meta_count
                       .with_tenant("t1")
                       .with_group_by_filter(["name"])
                       .with_limit(3)
                       .with_near_vector({ "vector" => [1.0, 2.0], "distance" => 0.5 })
                       .with_object_limit(10)
                       .build
    expect(q).to eq('{Aggregate{Thing(where: {path: ["name"] operator: Equal valueText: "a\\"b"} ' \
                    'groupBy: ["name"]nearVector: {vector: [1.0,2.0] distance: 0.5} objectLimit: 10' \
                    'tenant: "t1"limit: 3){meta{count}count {   mean     }}}}')
  end

  it "renders hybrid and nested where operands" do
    q = described_class.new("A")
                       .with_where({ "operator" => "And", "operands" => [
                                     { "path" => ["n"], "operator" => "GreaterThan", "valueInt" => 3 },
                                     { "path" => ["b"], "operator" => "Equal", "valueBoolean" => true }
                                   ] })
                       .with_hybrid({ "query" => "hi", "alpha" => 0.5, "properties" => %w[a b] })
                       .build
    expect(q).to eq('{Aggregate{A(where: {operator: And operands: [{path: ["n"] operator: GreaterThan valueInt: 3}, ' \
                    '{path: ["b"] operator: Equal valueBoolean: true}]} hybrid:{query: "hi", alpha: 0.5, ' \
                    'properties: ["a","b"]}){}}}')
  end
end
