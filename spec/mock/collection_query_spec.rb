# frozen_string_literal: true

require "spec_helper"

# Port of the query / gRPC search tests of mock_tests/test_collection.py and
# mock_tests/test_timeouts.py (test_timeout_grpc_query).
RSpec.describe "collection query (mock)" do
  include_context "mock weaviate"

  v1 = Weaviate::V1

  let(:client) { connect_mock_client }

  after { client.close }

  def search_reply_with(fields)
    Weaviate::V1::SearchReply.new(
      results: [
        Weaviate::V1::SearchResult.new(
          properties: Weaviate::V1::PropertiesResult.new(non_ref_props: Weaviate::V1::Properties.new(fields: fields))
        )
      ]
    )
  end

  it "test_year_zero" do
    reply = search_reply_with("date" => v1::Value.new(date_value: "0000-01-30T00:00:00Z"))
    grpc_impl { define_method(:search) { |_req, _call| reply } }
    collection = client.collections.use("YearZeroCollection")

    objs, warnings = Weaviate::Warnings.capture { collection.query.fetch_objects.objects }
    expect(objs[0].properties["date"]).to eq(Time.utc(1, 1, 1))
    expect(warnings[0]).to start_with("Con004")
  end

  it "test_empty_date" do
    reply = search_reply_with(
      "date" => v1::Value.new(date_value: ""),
      "dates" => v1::Value.new(
        list_value: v1::ListValue.new(date_values: v1::DateValues.new(values: ["", "2023-01-15T14:30:45.123456Z"]))
      )
    )
    grpc_impl { define_method(:search) { |_req, _call| reply } }
    collection = client.collections.use("EmptyDateCollection")

    objs, warnings = Weaviate::Warnings.capture { collection.query.fetch_objects.objects }
    expect(objs[0].properties["date"]).to be_nil
    expect(objs[0].properties["dates"]).to eq([nil, Time.utc(2023, 1, 15, 14, 30, Rational("45.123456"))])
    expect(warnings[0]).to start_with("Con006")
  end

  it "test_grpc_retry_logic" do
    grpc_impl do
      attr_reader :search_count

      define_method(:search) do |_req, _call|
        @search_count ||= 0
        if @search_count.zero?
          @search_count += 1
          raise GRPC::Internal, "Internal server error"
        end
        if @search_count == 1
          @search_count += 1
          raise GRPC::Unavailable, "Service is unavailable"
        end
        Weaviate::V1::SearchReply.new(
          results: [
            Weaviate::V1::SearchResult.new(
              properties: Weaviate::V1::PropertiesResult.new(
                non_ref_props: Weaviate::V1::Properties.new(fields: { "name" => Weaviate::V1::Value.new(text_value: "test") })
              )
            )
          ]
        )
      end
    end
    collection = client.collections.use("RetriesCollection")

    # checks first call correctly handles INTERNAL error
    expect { collection.query.fetch_objects }.to raise_error(Weaviate::Exceptions::WeaviateQueryError)

    # should perform one retry and then succeed subsequently
    objs = collection.query.fetch_objects.objects
    expect(objs.length).to eq(1)
    expect(objs[0].properties["name"]).to eq("test")
    expect(MockGrpcServer.impl.search_count).to eq(2)
  end

  it "test_grpc_forbidden_exception" do
    grpc_impl do
      def search(_req, _call)
        raise GRPC::PermissionDenied, "Permission denied"
      end
    end
    forbidden = client.collections.use("ForbiddenCollection")

    expect { forbidden.query.fetch_objects }.to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
    expect { forbidden.generate.fetch_objects(single_prompt: "x") }
      .to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
  end

  it "test_grpc_client_version_header" do
    grpc_impl do
      attr_reader :captured_metadata

      def search(_req, call)
        @captured_metadata = call.metadata.to_h
        Weaviate::V1::SearchReply.new
      end
    end
    collection = client.collections.use("MetadataCaptureCollection")
    collection.query.fetch_objects

    captured = MockGrpcServer.impl.captured_metadata
    expect(captured).to include("x-weaviate-client")
    expect(captured["x-weaviate-client"]).to eq("weaviate-client-ruby/#{Weaviate::VERSION}-sync")
  end

  it "sends the search request built from the query arguments" do
    grpc_impl do
      attr_reader :request

      def search(req, _call)
        @request = req
        Weaviate::V1::SearchReply.new(
          results: [
            Weaviate::V1::SearchResult.new(
              metadata: Weaviate::V1::MetadataResult.new(
                id_as_bytes: ["0123456789abcdef0123456789abcdef"].pack("H*"),
                distance: 0.25, distance_present: true,
                creation_time_unix: 1_700_000_000_123, creation_time_unix_present: true,
                vector_bytes: [1.0, 2.0].pack("e*")
              ),
              properties: Weaviate::V1::PropertiesResult.new(
                target_collection: "Things",
                non_ref_props: Weaviate::V1::Properties.new(
                  fields: {
                    "n" => Weaviate::V1::Value.new(int_value: 3),
                    "l" => Weaviate::V1::Value.new(
                      list_value: Weaviate::V1::ListValue.new(
                        int_values: Weaviate::V1::IntValues.new(values: [1, 2].pack("q<*"))
                      )
                    )
                  }
                )
              )
            )
          ]
        )
      end
    end
    q = Weaviate::Classes::Query
    collection = client.collections.use("things")
    res = collection.query.near_text("hello", limit: 2, filters: q::Filter.by_property("n").greater_than(1),
                                              include_vector: true, return_metadata: q::MetadataQuery.new(distance: true))

    req = MockGrpcServer.impl.request
    expect(req.collection).to eq("Things")
    expect(req.limit).to eq(2)
    expect(req.near_text.query.to_a).to eq(["hello"])
    expect(req.filters.operator).to eq(:OPERATOR_GREATER_THAN)
    expect(req.metadata.distance).to be(true)
    expect(req.metadata.vector).to be(true)

    obj = res.objects[0]
    expect(obj).to be_a(Weaviate::Outputs::Query::Object)
    expect(obj.uuid).to eq("01234567-89ab-cdef-0123-456789abcdef")
    expect(obj.collection).to eq("Things")
    expect(obj.properties).to eq("n" => 3, "l" => [1, 2])
    expect(obj.metadata.distance).to eq(0.25)
    expect(obj.metadata.creation_time).to eq(Time.at(Rational(1_700_000_000_123, 1000)).utc)
    expect(obj.vector).to eq("default" => [1.0, 2.0])
  end

  describe "timeouts" do
    let(:client) do
      no_auth_mock!
      connect_mock_client(
        additional_config: Weaviate::Config::AdditionalConfig.new(
          timeout: Weaviate::Config::Timeout.new(query: 0.5, insert: 1.5)
        )
      )
    end

    it "test_timeout_grpc_query" do
      grpc_impl do
        def search(_req, _call)
          sleep 1
          Weaviate::V1::SearchReply.new
        end
      end
      timeouts_collection = client.collections.use(MockContext::MOCK_CLASS["class"])
      expect { timeouts_collection.query.fetch_objects }.to raise_error(Weaviate::Exceptions::WeaviateQueryError)
    end
  end
end
