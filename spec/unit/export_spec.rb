# frozen_string_literal: true

# Port of test/test_export.py
RSpec.describe Weaviate::Export::ExportStatusReturn do
  # An export status as Weaviate's `GET /export/{backend}/{id}` returns it.
  def status_entry(**overrides)
    {
      "id" => "my-export",
      "backend" => "filesystem",
      "path" => "/tmp/exports/my-export",
      "classes" => ["Article"],
      "status" => "SUCCESS",
      "startedAt" => "2026-08-01T10:00:00.000Z",
      "completedAt" => "2026-08-01T10:05:00.000Z",
      "tookInMs" => 300_000
    }.merge(overrides.transform_keys(&:to_s))
  end

  it "test_status_return_maps_unset_completed_at_to_none" do
    # A running export reports Go's zero time as its completedAt.
    status = described_class.from_weaviate(
      status_entry(status: "TRANSFERRING", completedAt: "0001-01-01T00:00:00.000Z", tookInMs: nil)
    )

    expect(status.status).to eq(Weaviate::Export::ExportStatus::TRANSFERRING)
    expect(status.completed_at).to be_nil
  end

  it "test_status_return_keeps_set_completed_at" do
    status = described_class.from_weaviate(status_entry)

    expect(status.completed_at).to eq(Time.utc(2026, 8, 1, 10, 5, 0))
  end
end
