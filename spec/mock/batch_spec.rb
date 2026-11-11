# frozen_string_literal: true

require "spec_helper"

# Port of mock_tests/test_batch.py (sync tests; the async variant is out of scope).
RSpec.describe "batch (mock)" do
  include_context "mock weaviate"

  how_many = 1000
  mock_class = MockContext::MOCK_CLASS

  before { Weaviate::Collections::Batch.logger = Weaviate::Collections::Batch::BatchLogger.new(level: :fatal) }

  # Python fixture `canceled_stream_client`
  let(:client) do
    httpserver.expect_request("/v1/schema/#{mock_class["class"]}").respond_with_json(mock_class)
    connect_mock_client
  end

  after { client.close }

  # MockCanceledStreamWeaviateService
  def install_canceled_stream_service
    service = Class.new do
      attr_accessor :called, :uuids

      def initialize
        @called = false
        @uuids = Set.new
        @lock = Mutex.new
      end

      def batch_stream(requests, _call)
        unless @called
          @called = true
          raise GRPC::Cancelled, "context canceled"
        end
        Enumerator.new do |y|
          y << Weaviate::V1::BatchStreamReply.new(started: Weaviate::V1::BatchStreamReply::Started.new)
          requests.each do |request|
            if request.has_data?
              uuids = request.data.objects.values.map(&:uuid)
              @lock.synchronize { @uuids.merge(uuids) }
              y << Weaviate::V1::BatchStreamReply.new(acks: Weaviate::V1::BatchStreamReply::Acks.new(uuids: uuids))
            end
            break if request.has_stop?
          end
        end
      end
    end.new
    MockGrpcServer.impl = service
    service
  end

  # MockFailedObjectWeaviateService: rejects every other object, starting with the first.
  def install_failed_object_service
    service = Class.new do
      def initialize
        @seen = 0
      end

      def batch_stream(requests, _call)
        Enumerator.new do |y|
          y << Weaviate::V1::BatchStreamReply.new(started: Weaviate::V1::BatchStreamReply::Started.new)
          requests.each do |request|
            if request.has_data?
              uuids = []
              errors = []
              successes = []
              request.data.objects.values.each do |obj|
                uuids << obj.uuid
                if @seen.even?
                  errors << Weaviate::V1::BatchStreamReply::Results::Error.new(uuid: obj.uuid, error: "mock failure")
                else
                  successes << Weaviate::V1::BatchStreamReply::Results::Success.new(uuid: obj.uuid)
                end
                @seen += 1
              end
              y << Weaviate::V1::BatchStreamReply.new(acks: Weaviate::V1::BatchStreamReply::Acks.new(uuids: uuids))
              y << Weaviate::V1::BatchStreamReply.new(
                results: Weaviate::V1::BatchStreamReply::Results.new(errors: errors, successes: successes)
              )
            end
            break if request.has_stop?
          end
        end
      end
    end.new
    MockGrpcServer.impl = service
    service
  end

  it "test_ssb_canceled_stream" do
    collection = client.collections.use(mock_class["class"])
    service = install_canceled_stream_service
    collection.batch.stream do |batch|
      how_many.times { |i| batch.add_object({ "name" => "Object #{i}" }) }
    end
    expect(service.uuids.length).to eq(how_many)
  end

  it "test_ingest_has_errors_on_failed_object" do
    collection = client.collections.use(mock_class["class"])
    install_failed_object_service
    result = collection.data.ingest([{ "name" => "Object 1" }])
    expect(result.has_errors).to be(true)
    expect(result.errors.length).to eq(1)
  end

  it "test_ssb_ingest_reports_has_errors" do
    collection = client.collections.use(mock_class["class"])
    install_failed_object_service
    result = collection.data.ingest((0...4).lazy.map { |i| { "name" => "Object #{i}" } })
    expect(result.errors.length).to eq(2)
    expect(result.uuids.length).to eq(2)
    expect(result.has_errors).to be(true)
  end

  it "test_ssb_stream_reports_has_errors" do
    collection = client.collections.use(mock_class["class"])
    install_failed_object_service
    collection.batch.stream do |batch|
      4.times { |i| batch.add_object({ "name" => "Object #{i}" }) }
    end
    expect(collection.batch.failed_objects.length).to eq(2)
    expect(collection.batch.results.objs.has_errors).to be(true)
  end
end
