module Netbox
  class API::TenantsBase < API::EntityWSlug
  end

  class API::Tenants < API::TenantsBase
    include JSON::Serializable

    @[JSON::Field(key: "group")]
    property tenant_group : API::TenantGroups?

    property description : String
    property comments : String
  end
end
