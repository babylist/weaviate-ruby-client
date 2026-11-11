# frozen_string_literal: true

require "securerandom"

# Port of weaviate-python-client/integration/test_export.py
RSpec.describe "export", :integration do # rubocop:disable RSpec/DescribeClass
  export_mod = Weaviate::Export
  backend = export_mod::ExportStorage::FILESYSTEM
  collection_name = "ExportTestCollection"
  object_props = Array.new(5) { |i| { "title" => "object #{i}", "count" => i } }
  object_ids = %w[
    fd34ccf4-1a2a-47ad-8446-231839366c3f
    2653442b-05d8-4fa3-b46a-d4a152eb63bc
    55374edb-17de-487f-86cb-9a9fbc30823f
    124ff6aa-597f-44d0-8c13-62fbb1e66888
    f787386e-7d1c-481f-b8c3-3dbfd8bbad85
  ]

  let(:client) { client_factory }

  # Python uses a module-scoped fixture; here the collection is (re)created for every example.
  before do
    if client.connection.weaviate_version.is_lower_than(1, 37, 0)
      skip("Collection export is not supported in versions lower than 1.37.0")
    end
    client.collections.delete(collection_name)
    c = Weaviate::Classes::Config
    col = client.collections.create(
      collection_name,
      properties: [
        c::Property.new(name: "title", data_type: c::DataType::TEXT),
        c::Property.new(name: "count", data_type: c::DataType::INT)
      ]
    )
    object_props.each_with_index { |props, i| col.data.insert(props, uuid: object_ids[i]) }
  end

  after { client.collections.delete(collection_name) }

  # Generate a unique export ID based on the test name.
  def unique_export_id(name)
    IntegrationContext.sanitize_collection_name(name) + SecureRandom.uuid.delete("-")[0, 12]
  end

  def node_name = RSpec.current_example.description

  # Create an export with wait_for_completion=True.
  it "test_create_export_with_waiting" do
    export_id = unique_export_id(node_name)

    resp = client.export.create(
      export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
      include_collections: [collection_name], wait_for_completion: true
    )
    expect(resp.status).to eq(export_mod::ExportStatus::SUCCESS)
    expect(resp.collections).to include(collection_name)
  end

  # Create an export without waiting, then poll status.
  it "test_create_export_without_waiting" do
    export_id = unique_export_id(node_name)
    s = export_mod::ExportStatus

    resp = client.export.create(
      export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
      include_collections: [collection_name]
    )
    expect([s::STARTED, s::TRANSFERRING, s::SUCCESS]).to include(resp.status)

    # poll until done
    status = nil
    loop do
      status = client.export.get_status(export_id: export_id, backend: backend)
      expect([s::STARTED, s::TRANSFERRING, s::SUCCESS]).to include(status.status)
      break if status.status == s::SUCCESS

      sleep(0.1)
    end

    expect(status.export_id.downcase).to eq(export_id.downcase)
  end

  # Check status of a completed export.
  it "test_get_export_status" do
    export_id = unique_export_id(node_name)

    client.export.create(
      export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
      include_collections: [collection_name], wait_for_completion: true
    )

    status = client.export.get_status(export_id: export_id, backend: backend)
    expect(status.status).to eq(export_mod::ExportStatus::SUCCESS)
    expect(status.export_id.downcase).to eq(export_id.downcase)
    expect(status.backend).to eq(backend) # Python: BACKEND.value (Ruby enums are plain Strings)
  end

  # Create an export explicitly specifying parquet format.
  it "test_create_export_with_parquet_format" do
    export_id = unique_export_id(node_name)

    resp = client.export.create(
      export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
      include_collections: [collection_name], wait_for_completion: true
    )
    expect(resp.status).to eq(export_mod::ExportStatus::SUCCESS)
  end

  # Verify include_collections accepts both str and list.
  [[collection_name], collection_name].each do |include|
    it "test_create_export_include_as_str_and_list[#{include.inspect}]" do
      export_id = unique_export_id(node_name)

      resp = client.export.create(
        export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
        include_collections: include, wait_for_completion: true
      )
      expect(resp.status).to eq(export_mod::ExportStatus::SUCCESS)
      expect(resp.collections).to include(collection_name)
    end
  end

  # Cancel a running export.
  it "test_cancel_export" do
    export_id = unique_export_id(node_name)
    s = export_mod::ExportStatus

    resp = client.export.create(
      export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
      include_collections: [collection_name]
    )
    expect([s::STARTED, s::TRANSFERRING, s::SUCCESS]).to include(resp.status)

    client.export.cancel(export_id: export_id, backend: backend)

    # verify it's cancelled or already completed (race condition)
    start = Time.now
    status = nil
    while Time.now - start < 5
      status = client.export.get_status(export_id: export_id, backend: backend)
      break if [s::CANCELED, s::SUCCESS].include?(status.status)

      sleep(0.1)
    end
    expect([s::CANCELED, s::SUCCESS]).to include(status.status)
  end

  # Fail export on non-existing collection.
  it "test_fail_on_non_existing_collection" do
    export_id = unique_export_id(node_name)
    expect do
      client.export.create(
        export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
        include_collections: ["NonExistingCollection"], wait_for_completion: true
      )
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
  end

  # Fail when both include and exclude collections are set.
  it "test_fail_on_both_include_and_exclude" do
    export_id = unique_export_id(node_name)
    expect do
      client.export.create(
        export_id: export_id, backend: backend, file_format: export_mod::ExportFileFormat::PARQUET,
        include_collections: collection_name, exclude_collections: "SomeOther"
      )
    end.to raise_error(ArgumentError)
  end

  # Fail checking status for non-existing export.
  it "test_fail_status_for_non_existing_export" do
    export_id = unique_export_id(node_name)
    expect do
      client.export.get_status(export_id: export_id, backend: backend)
    end.to raise_error(Weaviate::Exceptions::UnexpectedStatusCodeException)
  end
end
