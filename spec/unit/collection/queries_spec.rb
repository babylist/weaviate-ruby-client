# frozen_string_literal: true

# Port of test/collection/test_queries.py (string syntax tests are commented out in Python as well)
RSpec.describe Weaviate::Collections::Queries::QueryCollection do
  let(:connection) do
    con = Weaviate::Connect::Connection.new(
      connection_params: Weaviate::Connect::ConnectionParams.from_url("http://localhost:8080", 50_051)
    )
    con.instance_variable_set(:@connected, true)
    con
  end

  let(:query) do
    described_class.new(connection: connection, name: "dummy", consistency_level: nil, tenant: nil,
                        validate_arguments: true)
  end

  def expect_invalid(&block)
    expect(&block).to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
  end

  it "test_bad_query_inputs" do
    # fetch_objects
    expect_invalid { query.fetch_objects(limit: "thing") }
    expect_invalid { query.fetch_objects(offset: "wrong") }
    expect_invalid { query.fetch_objects(after: 42) }
    expect_invalid { query.fetch_objects(filters: "wrong") }
    expect_invalid { query.fetch_objects(sort: "wrong") }
    expect_invalid { query.fetch_objects(include_vector: 42) }
    expect_invalid { query.fetch_objects(return_metadata: 42) }
    expect_invalid { query.fetch_objects(return_properties: 42) }
    expect_invalid { query.fetch_objects(return_references: "wrong") }

    # bm25
    expect_invalid { query.bm25(42) }
    expect_invalid { query.bm25("hi", query_properties: "wrong") }
    expect_invalid { query.bm25("hi", auto_limit: "wrong") }
    expect_invalid { query.bm25("hi", rerank: "wrong") }

    # hybrid
    expect_invalid { query.hybrid(42) }
    expect_invalid { query.hybrid("hi", query_properties: "wrong") }
    expect_invalid { query.hybrid("hi", alpha: "wrong") }
    expect_invalid { query.hybrid("hi", vector: "wrong") }
    expect_invalid { query.hybrid("hi", fusion_type: "wrong") }

    # near text
    expect_invalid { query.near_text(42) }
    expect_invalid { query.near_text("hi", certainty: "wrong") }
    expect_invalid { query.near_text("hi", distance: "wrong") }
    expect_invalid { query.near_text("hi", move_to: "wrong") }
    expect_invalid { query.near_text("hi", move_away: "wrong") }

    # near object
    expect_invalid { query.near_object(42) }

    # near vector
    expect_invalid { query.near_vector(42) }

    # near image
    expect_invalid { query.near_image(42) }
  end

  it "returns an empty result for fetch_objects_by_ids without ids, without a request" do
    expect(query.fetch_objects_by_ids([]).objects).to eq([])
  end

  it "rejects query profiling on old servers" do
    connection.weaviate_version = Weaviate::ServerVersion.from_string("1.36.0")
    expect { query.fetch_objects(return_metadata: Weaviate::Classes::Query::MetadataQuery.full_with_profile) }
      .to raise_error(Weaviate::Exceptions::WeaviateUnsupportedFeatureError)
  end
end
