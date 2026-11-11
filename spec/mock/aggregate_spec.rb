# frozen_string_literal: true

RSpec.describe "collection.aggregate against a mock Weaviate" do
  include_context "mock weaviate"

  Q = Weaviate::Classes::Query
  A = Weaviate::Classes::Aggregate

  it "aggregates over gRPC (>= 1.29)" do
    captured = nil
    grpc_impl do
      define_method(:aggregate) do |req, _call|
        captured = req
        Weaviate::V1::AggregateReply.new(
          single_result: Weaviate::V1::AggregateReply::Single.new(
            objects_count: 7,
            aggregations: Weaviate::V1::AggregateReply::Aggregations.new(aggregations: [
              Weaviate::V1::AggregateReply::Aggregations::Aggregation.new(
                property: "views",
                int: Weaviate::V1::AggregateReply::Aggregations::Aggregation::Integer.new(count: 7, mean: 2.5)
              )
            ])
          )
        )
      end
    end
    connect_mock_client do |client|
      res = client.collections.use("Article").aggregate.over_all(
        return_metrics: A::Metrics.new("views").integer(count: true, mean: true),
        filters: Q::Filter.by_property("views").greater_than(1)
      )
      expect(res.total_count).to eq(7)
      expect(res.properties["views"].mean).to eq(2.5)
      expect(res.properties["views"].maximum).to be_nil
      expect(captured.collection).to eq("Article")
      expect(captured.objects_count).to be(true)
      expect(captured.filters.operator).to eq(:OPERATOR_GREATER_THAN)
    end
  end

  it "groups over gRPC" do
    grpc_impl do
      def aggregate(_req, _call)
        Weaviate::V1::AggregateReply.new(
          grouped_results: Weaviate::V1::AggregateReply::Grouped.new(groups: [
            Weaviate::V1::AggregateReply::Group.new(
              objects_count: 2,
              grouped_by: Weaviate::V1::AggregateReply::Group::GroupedBy.new(path: ["cat"], text: "news")
            )
          ])
        )
      end
    end
    connect_mock_client do |client|
      res = client.collections.use("Article").aggregate.over_all(group_by: "cat")
      expect(res.groups.first.grouped_by.prop).to eq("cat")
      expect(res.groups.first.grouped_by.value).to eq("news")
      expect(res.groups.first.total_count).to eq(2)
    end
  end

  it "uses GraphQL for Weaviate < 1.29" do
    httpserver.clear
    httpserver.expect_request("/v1/.well-known/ready").respond_with_json({})
    httpserver.expect_request("/v1/meta").respond_with_json({ "version" => "1.28.0" })
    sent = nil
    httpserver.expect_request("/v1/graphql", method: "POST").respond_with_handler do |req|
      sent = req.json["query"]
      [200, { "content-type" => "application/json" },
       JSON.generate({ "data" => { "Aggregate" => { "Article" => [
         { "meta" => { "count" => 4 }, "views" => { "count" => 4, "sum" => 10 } }
       ] } } })]
    end
    connect_mock_client do |client|
      res = client.collections.use("Article").aggregate.over_all(
        return_metrics: A::Metrics.new("views").integer(count: true, sum_: true)
      )
      expect(res.total_count).to eq(4)
      expect(res.properties["views"].sum_).to eq(10)
    end
    expect(sent).to eq("{Aggregate{Article{meta{count}views { count      sum }}}}")
  end

  it "collection.length uses aggregate.over_all" do
    grpc_impl do
      def aggregate(_req, _call)
        Weaviate::V1::AggregateReply.new(single_result: Weaviate::V1::AggregateReply::Single.new(objects_count: 3))
      end
    end
    connect_mock_client { |client| expect(client.collections.use("Article").length).to eq(3) }
  end
end
