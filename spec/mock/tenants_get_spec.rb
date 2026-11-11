# frozen_string_literal: true

require "spec_helper"

# Port of mock_tests/test_tenants_get.py
RSpec.describe "tenants get (mock)" do
  include_context "mock weaviate"

  let(:status) { Weaviate::Classes::Tenants::TenantActivityStatus }

  # Python fixture `tenants_collection`
  let(:client) { connect_mock_client }
  let(:tenants_collection) do
    grpc_impl do
      def tenants_get(_req, _call)
        statuses = %i[HOT COLD FROZEN FREEZING UNFREEZING ACTIVE INACTIVE OFFLOADED OFFLOADING ONLOADING]
        Weaviate::V1::TenantsGetReply.new(
          tenants: statuses.each_with_index.map do |s, i|
            Weaviate::V1::Tenant.new(name: "tenant#{i + 1}", activity_status: :"TENANT_ACTIVITY_STATUS_#{s}")
          end
        )
      end
    end
    client.collections.use("TenantsGetCollectionName")
  end

  after { client.close }

  it "test_tenants_get" do
    tenants = tenants_collection.tenants.get.values
    expect(tenants.length).to eq(10)

    expected = [
      status::ACTIVE, status::INACTIVE, status::OFFLOADED, status::OFFLOADING, status::ONLOADING,
      status::ACTIVE, status::INACTIVE, status::OFFLOADED, status::OFFLOADING, status::ONLOADING
    ]
    expected.each_with_index do |activity_status, i|
      expect(tenants[i].name).to eq("tenant#{i + 1}")
      expect(tenants[i].activity_status).to eq(activity_status)
    end
  end
end
