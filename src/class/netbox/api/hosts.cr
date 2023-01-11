module Netbox
  class API::HostsBase < API::EntityWURL; end

  class API::HostsCommon < API::HostsBase
    class Status < API::ValueLabel; end
    use_json_discriminator "type", {vm: Netbox::API::VirtualMachines, host: Netbox::API::Hosts}
    property type : String
    
    property status : Status
    property primary_ip : API::IPsBase?
    property primary_ip4 : API::IPsBase?
    property primary_ip6 : API::IPsBase?
    property site : API::SitesBase?
    property tenant : API::TenantsBase
    property platform : API::Platform?
    property cluster : API::ClustersBase?
    property comments : String
    property tags : Array(API::TagsBase)?
    property created : String
    property last_updated : String
    property local_context_data : String?

    def host_name
      {@name, @display}.each do |psbl_name|
        if psbl_name && psbl_name =~ /^(?i:[ks][a-z]{2}(?:-[a-z]+){2})/
          return psbl_name.downcase
        end
      end
      nil
    end
  end

  class API::Hosts < API::HostsCommon
#    include JSON::Serializable

    class Face < API::ValueLabel; end

    @[JSON::Field(key: "device_role")]
    property role : API::DeviceRole

    property display_name : String
    property device_type : API::DeviceTypesBase
    property serial : String?
    property asset_tag : String?
    property location : API::Location?
    property rack : API::Rack?
    property position : Int32?
    property face : Face?
    property parent_device : API::Entity?
  end
end
