module Netbox
  class API::VirtualMachines < API::HostsCommon
    property role : API::RolesBase?
    property vcpus : String
    property memory : Int32?
    property disk : Int32?
  end
end
