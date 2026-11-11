# frozen_string_literal: true

# Port of test/test_backup.py
RSpec.describe Weaviate::Backup::BackupListReturn do
  # A single item as Weaviate's `GET /backups/{backend}` returns it.
  def list_entry(**overrides)
    {
      "id" => "my-backup",
      "classes" => ["Article"],
      "status" => "SUCCESS",
      "startedAt" => "2026-08-01T10:00:00.000Z",
      "completedAt" => "2026-08-01T10:05:00.000Z",
      "size" => 1.5
    }.merge(overrides.transform_keys(&:to_s))
  end

  it "test_list_return_exposes_incremental_base_backup_id" do
    backup = described_class.from_weaviate(list_entry(incremental_base_backup_id: "base-backup"))

    expect(backup.incremental_base_backup_id).to eq("base-backup")
    expect(backup.backup_id).to eq("my-backup")
    expect(backup.collections).to eq(["Article"])
    expect(backup.status).to eq(Weaviate::Outputs::Backup::BackupStatus::SUCCESS)
    expect(backup.started_at).to eq(Time.utc(2026, 8, 1, 10, 0, 0))
  end

  {
    "field_omitted" => {},
    "field_null" => { incremental_base_backup_id: nil }
  }.each do |id, overrides|
    it "test_list_return_defaults_incremental_base_backup_id_to_none[#{id}]" do
      # The server omits the field for non-incremental backups, and only populates
      # it for callers it has confirmed as root, so absent must not be an error.
      expect(described_class.from_weaviate(list_entry(**overrides)).incremental_base_backup_id).to be_nil
    end
  end
end

RSpec.describe "Weaviate::Backup config models" do
  it "serialises BackupConfigCreate to the REST field names, dropping chunk_size" do
    config = Weaviate::Classes::Backup::BackupConfigCreate.new(
      cpu_percentage: 50, chunk_size: 128,
      compression_level: Weaviate::Classes::Backup::BackupCompressionLevel::BEST_SPEED
    )
    expect(config.to_dict).to eq({ "CPUPercentage" => 50, "CompressionLevel" => "BestSpeed" })
    expect(Weaviate::Classes::Backup::BackupConfigRestore.new.to_dict).to eq({})
  end

  it "serialises backup locations" do
    loc = Weaviate::Classes::Backup::BackupLocation::S3.new(path: "/p", bucket: "b")
    expect(loc.to_dict).to eq({ "path" => "/p", "bucket" => "b" })
    expect(Weaviate::Classes::Backup::BackupLocation::FileSystem.new(path: "/x").to_dict).to eq({ "path" => "/x" })
  end

  it "validates create/restore arguments like the Python client" do
    validate = lambda do |**kw|
      Weaviate::Backup::Backup.get_and_validate_create_restore_arguments(
        **{ backup_id: "ID", backend: "S3", include_classes: nil, exclude_classes: nil,
            wait_for_completion: false }.merge(kw)
      )
    end
    expect(validate.call(include_classes: "article")).to eq(["id", "s3", ["Article"], []])
    expect { validate.call(backup_id: 1) }.to raise_error(TypeError, /'backup_id' must be of type str/)
    expect { validate.call(wait_for_completion: "yes") }.to raise_error(TypeError, /wait_for_completion/)
    expect { validate.call(include_classes: "a", exclude_classes: "b") }
      .to raise_error(TypeError, "Either 'include_classes' OR 'exclude_classes' can be set, not both.")
    expect { validate.call(backend: "nope") }.to raise_error(ArgumentError, /'backend' must have one of these values/)
  end
end
