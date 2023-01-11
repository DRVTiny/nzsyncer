module Netbox
  class API::TenantGroups
    include JSON::Serializable
    property id : Int32
    property name : String
    property slug : String
    property url : String
  end
end
