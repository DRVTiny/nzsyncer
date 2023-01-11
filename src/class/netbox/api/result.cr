require "./*"

module Netbox
  class API::Result
    include JSON::Serializable
    property count : Int32
    property next : String?
    property previous : String?
    property results : Array(API::Tenants) | Array(API::VirtualMachines) | Array(API::Hosts)
  end
end
