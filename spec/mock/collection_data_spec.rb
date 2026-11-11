# frozen_string_literal: true

require "spec_helper"

# Port of the data / batch / tenants parts of mock_tests/test_timeouts.py and mock_tests/test_collection.py
# (test_closed_connection, test_grpc_retry_logic, test_grpc_forbidden_exception, the stream_cancel fixture),
# plus REST payload checks for collection.data and collection.tenants.
RSpec.describe "collection data / batch / tenants (mock)" do
  include_context "mock weaviate"

  mock_class = MockContext::MOCK_CLASS

  before { Weaviate::Collections::Batch.logger = Weaviate::Collections::Batch::BatchLogger.new(level: :fatal) }
  # background batch threads abandoned by a test may still log after it finished, so the quiet logger stays

  def with_client(**kwargs)
    client = connect_mock_client(**kwargs)
    yield client
  ensure
    client&.close
  end

  def timeout_config(**kwargs)
    Weaviate::Config::AdditionalConfig.new(timeout: Weaviate::Config::Timeout.new(**kwargs))
  end

  describe "timeouts (mock_tests/test_timeouts.py)" do
    # Python fixture `weaviate_timeouts_mock` + `timeouts_collection`
    def with_timeouts_collection
      no_auth_mock!
      httpserver.expect_request("/v1/schema/#{MockContext::MOCK_CLASS["class"]}", method: "GET").respond_with_handler do |_req|
        sleep 1
        [200, { "content-type" => "application/json" }, JSON.generate({ "doesn't" => "matter" })]
      end
      httpserver.expect_request("/v1/objects", method: "POST").respond_with_handler do |_req|
        sleep 2
        [200, { "content-type" => "application/json" }, JSON.generate({ "doesn't" => "matter" })]
      end
      grpc_impl do
        def batch_objects(_req, _call)
          sleep 2
          Weaviate::V1::BatchObjectsReply.new
        end
      end
      with_client(additional_config: timeout_config(query: 0.5, insert: 1.5)) do |client|
        yield client.collections.use(MockContext::MOCK_CLASS["class"])
      end
    end

    it "test_timeout_rest_insert" do
      with_timeouts_collection do |collection|
        expect { collection.data.insert(properties: { "what" => "ever" }) }
          .to raise_error(Weaviate::Exceptions::WeaviateTimeoutError)
      end
    end

    it "test_timeout_grpc_insert" do
      with_timeouts_collection do |collection|
        expect { collection.data.insert_many([{ "what" => "ever" }]) }
          .to raise_error(Weaviate::Exceptions::WeaviateQueryError, /Deadline Exceeded/i)
      end
    end

    it "test_batch_fixed_size_deadline_uses_insert_timeout" do
      batch_insert_timeout = 5
      httpserver.expect_request("/v1/schema/#{mock_class["class"]}").respond_with_json(mock_class)
      service = Class.new do
        attr_reader :captured_time_remaining

        def initialize
          @captured_time_remaining = -1.0
        end

        def batch_objects(_req, call)
          @captured_time_remaining = call.deadline.to_f - Time.now.to_f
          Weaviate::V1::BatchObjectsReply.new
        end
      end.new
      MockGrpcServer.impl = service
      with_client(additional_config: timeout_config(insert: batch_insert_timeout)) do |client|
        collection = client.collections.use(mock_class["class"])
        collection.batch.fixed_size(batch_size: 1) { |batch| batch.add_object({ "what" => "ever" }) }
      end
      expect((service.captured_time_remaining - batch_insert_timeout).abs).to be < 1
    end

    it "test_batch_fixed_size_times_out_when_insert_exceeded" do
      short = 0.5
      httpserver.expect_request("/v1/schema/#{mock_class["class"]}").respond_with_json(mock_class)
      grpc_impl do
        def batch_objects(_req, _call)
          sleep 1.5
          Weaviate::V1::BatchObjectsReply.new
        end
      end
      with_client(additional_config: timeout_config(insert: short)) do |client|
        collection = client.collections.use(mock_class["class"])
        collection.batch.fixed_size(batch_size: 1) { |batch| batch.add_object({ "what" => "ever" }) }
        failed = collection.batch.failed_objects
        expect(failed.length).to eq(1)
        expect(failed[0].message).to include("Deadline Exceeded")
      end
    end
  end

  it "test_closed_connection (insert_many)" do
    auth_mock!
    client = Weaviate::Client.new(
      connection_params: Weaviate::Connect::ConnectionParams.new(
        grpc: Weaviate::Connect::ProtocolParams.new(host: MockContext::MOCK_IP, port: MockContext::MOCK_PORT_GRPC,
                                                    secure: false),
        http: Weaviate::Connect::ProtocolParams.new(host: MockContext::MOCK_IP, port: MockContext::MOCK_PORT,
                                                    secure: false)
      )
    )
    expect { client.collections.use("Test").data.insert_many([{}]) }
      .to raise_error(Weaviate::Exceptions::WeaviateClosedClientError)
  end

  it "test_grpc_retry_logic (tenants)" do
    service = Class.new do
      attr_reader :tenants_count

      def initialize
        @tenants_count = 0
      end

      def tenants_get(_req, _call)
        if @tenants_count.zero?
          @tenants_count += 1
          raise GRPC::Internal, "Internal server error"
        end
        if @tenants_count == 1
          @tenants_count += 1
          raise GRPC::Unavailable, "Service is unavailable"
        end
        Weaviate::V1::TenantsGetReply.new(
          tenants: [Weaviate::V1::Tenant.new(name: "tenant1", activity_status: :TENANT_ACTIVITY_STATUS_ACTIVE)]
        )
      end
    end.new
    MockGrpcServer.impl = service
    with_client do |client|
      collection = client.collections.use("RetriesCollection")
      # checks first call correctly handles error that isn't UNAVAILABLE
      expect { collection.tenants.get }.to raise_error(Weaviate::Exceptions::WeaviateTenantGetError)

      # should perform one retry and then succeed subsequently
      tenants = collection.tenants.get.values
      expect(tenants.length).to eq(1)
      expect(tenants[0].name).to eq("tenant1")
      expect(service.tenants_count).to eq(2)
    end
  end

  it "test_grpc_forbidden_exception (tenants / delete_many / insert_many)" do
    grpc_impl do
      def tenants_get(_req, _call) = raise(GRPC::PermissionDenied, "Permission denied")
      def batch_objects(_req, _call) = raise(GRPC::PermissionDenied, "Permission denied")
      def batch_delete(_req, _call) = raise(GRPC::PermissionDenied, "Permission denied")
    end
    with_client do |client|
      forbidden = client.collections.use("ForbiddenCollection")
      expect { forbidden.tenants.get }.to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
      expect { forbidden.data.delete_many(where: Weaviate::Classes::Query::Filter.by_property("name").equal("test")) }
        .to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
      expect { forbidden.data.insert_many([{ "name" => "test" }]) }
        .to raise_error(Weaviate::Exceptions::InsufficientPermissionsError)
    end
  end

  # Python fixture `stream_cancel`: the server never answers the stream; the batch must still terminate
  # (after at most insert timeout + 5s) instead of hanging forever.
  it "test_stream_cancel" do
    name = "StreamCancelCollection"
    httpserver.expect_request("/v1/schema/#{name}").respond_with_data("", status: 404)
    grpc_impl do
      def batch_stream(_requests, call)
        Enumerator.new do |_y|
          deadline = Time.now + 10
          sleep 0.1 while !call.cancelled? && Time.now < deadline
          raise GRPC::DeadlineExceeded, "Deadline exceeded"
        end
      end
    end
    with_client(additional_config: timeout_config(insert: 1)) do |client|
      collection = client.collections.use(name)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      collection.batch.stream { |batch| batch.add_object({ "name" => "x" }) }
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 9
    end
  end

  describe "client-side batching" do
    let(:uuid) { "7cf4b4f3-a1a2-4bd5-9e57-b9b0ed0bb6c5" }
    let(:to_uuid) { "2a9c5ba0-0eba-4d41-a6c8-0bfaaa2fe0e5" }

    def install_recording_batch_service(fail_names: [])
      service = Class.new do
        attr_reader :objects

        def initialize(fail_names)
          @objects = []
          @fail_names = fail_names
          @lock = Mutex.new
        end

        def batch_objects(req, _call)
          errors = []
          req.objects.each_with_index do |obj, i|
            @lock.synchronize { @objects << obj }
            name = obj.properties.non_ref_properties.to_h["name"]
            errors << Weaviate::V1::BatchObjectsReply::BatchError.new(index: i, error: "bad") if @fail_names.include?(name)
          end
          Weaviate::V1::BatchObjectsReply.new(errors: errors)
        end
      end.new(fail_names)
      MockGrpcServer.impl = service
      service
    end

    it "collection.batch.dynamic sends objects over gRPC and references over REST" do
      httpserver.expect_request("/v1/schema/#{MockContext::MOCK_CLASS["class"]}").respond_with_json(MockContext::MOCK_CLASS)
      refs = []
      httpserver.expect_request("/v1/batch/references", method: "POST").respond_with_handler do |req|
        refs.concat(req.json)
        [200, { "content-type" => "application/json" }, JSON.generate(req.json.map { { "result" => {} } })]
      end
      service = install_recording_batch_service
      with_client do |client|
        collection = client.collections.use(MockContext::MOCK_CLASS["class"])
        collection.batch.dynamic do |batch|
          5.times { |i| batch.add_object({ "name" => "obj#{i}" }) }
          batch.add_object(properties: { "name" => "with-uuid" }, uuid: uuid)
          batch.add_reference(uuid, from_property: "ref", to: to_uuid)
        end
        expect(collection.batch.failed_objects).to be_empty
        expect(collection.batch.results.objs.uuids.length).to eq(6)
      end
      expect(service.objects.length).to eq(6)
      expect(refs).to eq([{ "from" => "weaviate://localhost/#{MockContext::MOCK_CLASS["class"]}/#{uuid}/ref",
                            "to" => "weaviate://localhost/#{to_uuid}" }])
    end

    it "client.batch.fixed_size reports failed objects" do
      httpserver.expect_request("/v1/schema").respond_with_json({ "classes" => [] })
      install_recording_batch_service(fail_names: ["bad"])
      with_client do |client|
        client.batch.fixed_size(batch_size: 2) do |batch|
          batch.add_object("Test", properties: { "name" => "good" })
          batch.add_object(collection: "Test", properties: { "name" => "bad" }, tenant: "t1")
          batch.add_object("Test", properties: { "name" => "good2" })
        end
        expect(client.batch.failed_objects.length).to eq(1)
        expect(client.batch.failed_objects[0].object_.properties).to eq({ "name" => "bad" })
        expect(client.batch.failed_objects[0].object_.tenant).to eq("t1")
        expect(client.batch.results.objs.uuids.length).to eq(2)
      end
    end

    it "raises WeaviateBatchValidationError for invalid references" do
      httpserver.expect_request("/v1/schema").respond_with_json({ "classes" => [] })
      install_recording_batch_service
      with_client do |client|
        expect do
          client.batch.dynamic { |batch| batch.add_reference("not-a-uuid", from_collection: "A", from_property: "p", to: uuid) }
        end.to raise_error(Weaviate::Exceptions::WeaviateBatchValidationError)
      end
    end
  end

  describe "data REST payloads" do
    let(:uuid) { "7cf4b4f3-a1a2-4bd5-9e57-b9b0ed0bb6c5" }
    let(:to_uuid) { "2a9c5ba0-0eba-4d41-a6c8-0bfaaa2fe0e5" }

    it "inserts with serialised properties, references, vector and tenant" do
      body = nil
      httpserver.expect_request("/v1/objects", method: "POST").respond_with_handler do |req|
        body = req.json
        [200, { "content-type" => "application/json" }, "{}"]
      end
      with_client do |client|
        collection = client.collections.use("Test").with_tenant("t1")
        t = Time.utc(2024, 1, 2, 3, 4, 5)
        res = collection.data.insert(
          {
            "date" => t, "geo" => Weaviate::Classes::Data::GeoCoordinate.new(latitude: 1.0, longitude: 2.0),
            "phone" => Weaviate::Classes::Data::PhoneNumber.new(number: "0123", default_country: "NL"),
            nested: { "dates" => [t] }
          },
          references: { "ref" => to_uuid,
                        "multi" => Weaviate::Classes::Query::ReferenceToMulti.new(target_collection: "Other",
                                                                                  uuids: [to_uuid]) },
          uuid: uuid, vector: [0.1, 0.2]
        )
        expect(res).to eq(uuid)
      end
      expect(body).to eq(
        "class" => "Test", "id" => uuid, "tenant" => "t1", "vector" => [0.1, 0.2],
        "properties" => {
          "date" => "2024-01-02T03:04:05.000000Z",
          "geo" => { "latitude" => 1.0, "longitude" => 2.0 },
          "phone" => { "input" => "0123", "defaultCountry" => "NL" },
          "nested" => { "dates" => ["2024-01-02T03:04:05.000000Z"] },
          "ref" => [{ "beacon" => "weaviate://localhost/#{to_uuid}" }],
          "multi" => [{ "beacon" => "weaviate://localhost/Other/#{to_uuid}" }]
        }
      )
    end

    it "validates insert arguments" do
      with_client do |client|
        expect { client.collections.use("Test").data.insert(nil) }
          .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError, /properties/)
      end
    end

    it "deletes by id, checks existence and replaces references" do
      no_auth_mock!
      httpserver.expect_request("/v1/objects/Test/#{uuid}", method: "DELETE").respond_with_data("", status: 204)
      httpserver.expect_request("/v1/objects/Test/#{uuid}", method: "HEAD").respond_with_data("", status: 404)
      httpserver.expect_request("/v1/objects/Test/#{uuid}/references/ref", method: "PUT",
                                                                         json: [{ "beacon" => "weaviate://localhost/#{to_uuid}" }])
                .respond_with_json({})
      with_client do |client|
        data = client.collections.use("Test").data
        expect(data.delete_by_id(uuid)).to be(true)
        expect(data.exists(uuid)).to be(false)
        expect(data.reference_replace(uuid, from_property: "ref", to: [to_uuid])).to be_nil
      end
      httpserver.check_assertions
    end

    it "reference_add_many reports failed references" do
      httpserver.expect_request("/v1/batch/references", method: "POST").respond_with_json(
        [{ "result" => { "status" => "SUCCESS" } },
         { "result" => { "status" => "FAILED", "errors" => { "error" => [{ "message" => "boom" }] } } }]
      )
      with_client do |client|
        res = client.collections.use("Test").data.reference_add_many(
          [Weaviate::Classes::Data::DataReference.new(from_property: "ref", from_uuid: uuid, to_uuid: to_uuid),
           Weaviate::Classes::Data::DataReferenceMulti.new(from_property: "ref", from_uuid: uuid, to_uuid: to_uuid,
                                                           target_collection: "Other")]
        )
        expect(res.has_errors).to be(true)
        expect(res.errors[1].message).to eq("boom")
        expect(res.errors[1].reference.to_object_collection).to eq("Other")
      end
    end

    it "insert_many returns uuids and errors" do
      grpc_impl do
        def batch_objects(req, _call)
          raise "unexpected" unless req.objects.length == 2 && req.objects[1].uuid == "7cf4b4f3-a1a2-4bd5-9e57-b9b0ed0bb6c5"

          Weaviate::V1::BatchObjectsReply.new(errors: [Weaviate::V1::BatchObjectsReply::BatchError.new(index: 0,
                                                                                                         error: "bad")])
        end
      end
      with_client do |client|
        res = client.collections.use("Test").data.insert_many(
          [{ "a" => 1 }, Weaviate::Classes::Data::DataObject.new(properties: { "a" => 2 }, uuid: uuid)]
        )
        expect(res.has_errors).to be(true)
        expect(res.errors[0].message).to eq("bad")
        expect(res.uuids).to eq({ 1 => uuid })
      end
    end
  end

  describe "tenants REST payloads" do
    it "creates, updates in batches and checks tenants" do
      created = nil
      updates = []
      httpserver.expect_request("/v1/schema/Test/tenants", method: "POST").respond_with_handler do |req|
        created = req.json
        [200, { "content-type" => "application/json" }, "[]"]
      end
      httpserver.expect_request("/v1/schema/Test/tenants", method: "PUT").respond_with_handler do |req|
        updates << req.json
        [200, { "content-type" => "application/json" }, "[]"]
      end
      httpserver.expect_request("/v1/schema/Test/tenants/t1", method: "HEAD").respond_with_data("", status: 200)
      httpserver.expect_request("/v1/schema/Test/tenants/nope", method: "GET").respond_with_data("", status: 404)
      tn = Weaviate::Classes::Tenants
      with_client do |client|
        tenants = client.collections.use("Test").tenants
        tenants.create(["t1", tn::Tenant.new(name: "t2", activity_status: tn::TenantActivityStatus::INACTIVE)])
        tenants.deactivate((0...150).map { |i| "t#{i}" })
        expect(tenants.exists("t1")).to be(true)
        expect(tenants.get_by_name("nope")).to be_nil
        expect { tenants.create(tn::Tenant.new(name: "x", activity_status: tn::TenantActivityStatus::OFFLOADED)) }
          .to raise_error(Weaviate::Exceptions::WeaviateInvalidInputError)
      end
      expect(created).to eq([{ "name" => "t1", "activityStatus" => "HOT" }, { "name" => "t2", "activityStatus" => "COLD" }])
      expect(updates.map(&:length)).to eq([100, 50])
      expect(updates[0][0]).to eq({ "name" => "t0", "activityStatus" => "COLD" })
    end
  end
end
