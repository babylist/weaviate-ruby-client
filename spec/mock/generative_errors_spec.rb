# frozen_string_literal: true

# Port of mock_tests/test_generative_errors.py (async variants are out of scope for the Ruby client)
RSpec.describe "generative query errors against a mock Weaviate" do
  include_context "mock weaviate"

  let(:client) do
    connect_mock_client(skip_init_checks: true,
                        additional_config: Weaviate::Config::AdditionalConfig.new(
                          timeout: Weaviate::Config::Timeout.new(query: 1)
                        ))
  end

  after { client.close }

  def serve_search_error(error_class, details)
    grpc_impl do
      attr_reader :requests

      define_method(:search) do |req, _call|
        (@requests ||= []) << req
        raise error_class, details
      end
    end
  end

  it "test_generative_retry_error" do
    no_auth_mock!
    serve_search_error(GRPC::Unavailable, "generative provider failed")
    allow_any_instance_of(Weaviate::Connect::Retry).to receive(:sleep) # rubocop:disable RSpec/AnyInstance

    expect { client.collections.use("Test").generate.fetch_objects(grouped_task: "Summarize") }
      .to raise_error(Weaviate::Exceptions::WeaviateGenerativeQueryError, /generative provider failed/)
    expect(MockGrpcServer.impl.requests.length).to eq(6)
    expect(MockGrpcServer.impl.requests).to all(have_attributes(has_generative?: true))
  end

  it "test_generative_internal_error" do
    no_auth_mock!
    serve_search_error(GRPC::Internal, "generative provider failed")

    expect { client.collections.use("Test").generate.fetch_objects(grouped_task: "Summarize") }
      .to raise_error(Weaviate::Exceptions::WeaviateGenerativeQueryError) { |e|
        expect(e).to be_a(Weaviate::Exceptions::WeaviateQueryError)
        expect(e.message).to include("generative provider failed")
      }
  end

  it "test_query_error_is_not_generative" do
    no_auth_mock!
    serve_search_error(GRPC::Internal, "search failed")

    expect { client.collections.use("Test").query.fetch_objects }
      .to raise_error(Weaviate::Exceptions::WeaviateQueryError) { |e|
        expect(e).not_to be_a(Weaviate::Exceptions::WeaviateGenerativeQueryError)
      }
  end

  it "test_generative_permissions_are_unchanged" do
    no_auth_mock!
    serve_search_error(GRPC::PermissionDenied, "Permission denied")

    expect { client.collections.use("Test").generate.fetch_objects(grouped_task: "Summarize") }
      .to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
  end
end
