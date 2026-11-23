# frozen_string_literal: true

# Port of mock_tests/test_replication_scale.py (HTTP-contract tests for replication scale plans).
RSpec.describe "replication scale plans (mock)" do
  include_context "mock weaviate"

  scale_path = "/v1/replication/scale"
  plan_id = "32536c0e-09e1-4ea1-a2c5-e85af10a9d58"
  operation_id = "47b26ba1-6bc9-41f8-a655-8b9a5b60e1a3"
  second_operation_id = "5fef6289-28d2-4ea2-82a9-48eb501200cd"

  let(:r) { Weaviate::Outputs::Replication }
  let(:server_version) { "1.35.0" }

  # Override the shared mock's fixed version for branch-boundary cases.
  before do
    httpserver.clear
    httpserver.expect_request("/v1/.well-known/ready").respond_with_json({})
    httpserver.expect_request("/v1/meta").respond_with_json({ "version" => server_version })
    httpserver.expect_request("/v1/nodes").respond_with_json({ "nodes" => [{ "name" => "node1", "status" => "HEALTHY" }] })
    no_auth_mock!
  end

  after { @client&.close }

  def client
    @client ||= connect_mock_client
  end

  it "test_generate_scale_plan_request_and_parsing" do
    # Capitalize the GET collection and parse ordered additions and omitted addNodes.
    httpserver.expect_request(scale_path, method: "GET",
                                          query: { "collection" => "ArticleArchive", "replicationFactor" => "3" })
              .respond_with_json(
                {
                  "planId" => plan_id,
                  "collection" => "ArticleArchive",
                  "shardScaleActions" => {
                    "shard-a" => { "removeNodes" => ["node4"], "addNodes" => { "node3" => "node4", "node2" => "node1" } },
                    "shard-b" => { "removeNodes" => ["node2"] }
                  }
                }
              )

    result = client.cluster.replications.generate_scale_plan(collection: "articleArchive", replication_factor: 3)

    expect(result).to eq(
      r::ReplicationScalePlan.new(
        plan_id: plan_id,
        collection: "ArticleArchive",
        shard_scale_actions: {
          "shard-a" => r::ShardScaleActions.new(
            remove_nodes: ["node4"],
            add_nodes: [
              r::ReplicaAddition.new(target_node: "node3", source_node: "node4"),
              r::ReplicaAddition.new(target_node: "node2", source_node: "node1")
            ]
          ),
          "shard-b" => r::ShardScaleActions.new(remove_nodes: ["node2"], add_nodes: [])
        }
      )
    )
    httpserver.check_assertions
  end

  it "test_apply_scale_plan_serialization_and_result_parsing" do
    # Preserve collection spelling, serialize every shard, and return UUID operation IDs.
    plan = r::ReplicationScalePlan.new(
      plan_id: plan_id,
      collection: "article",
      shard_scale_actions: {
        "shard-a" => r::ShardScaleActions.new(
          remove_nodes: [],
          add_nodes: [
            r::ReplicaAddition.new(target_node: "node2", source_node: "node1"),
            r::ReplicaAddition.new(target_node: "node3", source_node: nil)
          ]
        ),
        "shard-b" => r::ShardScaleActions.new(
          remove_nodes: ["node1"], add_nodes: [r::ReplicaAddition.new(target_node: "node2", source_node: "node1")]
        ),
        "shard-c" => r::ShardScaleActions.new(remove_nodes: ["node2"], add_nodes: [])
      }
    )
    httpserver.expect_request(
      scale_path, method: "POST",
                  json: {
                    "planId" => plan_id,
                    "collection" => "article",
                    "shardScaleActions" => {
                      "shard-a" => { "removeNodes" => [], "addNodes" => { "node2" => "node1", "node3" => nil } },
                      "shard-b" => { "removeNodes" => ["node1"], "addNodes" => { "node2" => "node1" } },
                      "shard-c" => { "removeNodes" => ["node2"], "addNodes" => {} }
                    }
                  }
    ).respond_with_json(
      { "planId" => plan_id, "collection" => "article", "operationIds" => [operation_id, second_operation_id] }
    )

    result = client.cluster.replications.apply_scale_plan(plan: plan)

    expect(result).to eq(
      r::ReplicationScaleApplyResult.new(
        plan_id: plan_id, collection: "article", operation_ids: [operation_id, second_operation_id]
      )
    )
    httpserver.check_assertions
  end

  it "test_apply_scale_plan_rejects_duplicate_target_nodes" do
    # Reject duplicate targets within one shard before making a request.
    plan = r::ReplicationScalePlan.new(
      plan_id: plan_id,
      collection: "Article",
      shard_scale_actions: {
        "shard-a" => r::ShardScaleActions.new(
          remove_nodes: [],
          add_nodes: [
            r::ReplicaAddition.new(target_node: "node3", source_node: "node1"),
            r::ReplicaAddition.new(target_node: "node3", source_node: "node2")
          ]
        )
      }
    )

    client
    httpserver.log.clear
    expect { client.cluster.replications.apply_scale_plan(plan: plan) }
      .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError) { |e|
        expect(e.message).to include("shard-a")
        expect(e.message).to include("node3")
      }
    expect(httpserver.log).to eq([])
  end

  %w[GET POST].each do |method|
    [
      ["1.31.19", false],
      ["1.31.20", true],
      ["1.32.16", false],
      ["1.32.17", true],
      ["1.33.4", false],
      ["1.33.5", true],
      ["1.34.0", false],
      ["1.34.1", true]
    ].each do |version, supported|
      context "with server version #{version}" do
        let(:server_version) { version }

        it "test_scale_methods_enforce_minimum_versions[#{version}-#{supported}-#{method}]" do
          # Enforce each branch's backport boundary for both public methods.
          plan = r::ReplicationScalePlan.new(plan_id: plan_id, collection: "Article", shard_scale_actions: {})
          if method == "GET"
            call = -> { client.cluster.replications.generate_scale_plan(collection: "Article", replication_factor: 3) }
            response = { "planId" => plan_id, "collection" => "Article", "shardScaleActions" => {} }
            expected = plan
          else
            call = -> { client.cluster.replications.apply_scale_plan(plan: plan) }
            response = { "planId" => plan_id, "collection" => "Article", "operationIds" => [] }
            expected = r::ReplicationScaleApplyResult.new(plan_id: plan_id, collection: "Article", operation_ids: [])
          end

          client
          httpserver.log.clear
          if supported
            httpserver.expect_request(scale_path, method: method).respond_with_json(response)
            expect(call.call).to eq(expected)
            expect(httpserver.log.map(&:path)).to include(scale_path)
            httpserver.check_assertions
          else
            expect { call.call }.to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError) { |e|
              expect(e.message).to include(version)
              %w[1.31.20 1.32.17 1.33.5 1.34.1].each { |minimum| expect(e.message).to include(minimum) }
            }
            expect(httpserver.log).to eq([])
          end
        end
      end
    end
  end
end
