module Netbox
  enum EType
    VirtualMachines
    Hosts
    Tenants
  end
  
  class API::Entity
    include JSON::Serializable
    property id : Int32
    property name : String?
    property display : String?
  end

  class API::EntityWSlug < API::Entity
    property slug : String
  end

  class API::EntityWURL < API::Entity
    property url : String
  end

  class API::EntityWSlugAndURL < API::Entity
    property slug : String
    property url : String
  end

  class API::EntityExtended < API::EntityWSlugAndURL
    property display_name : String
  end

  class API::ValueLabel
    include JSON::Serializable
    property value : String
    property label : String
  end
end
