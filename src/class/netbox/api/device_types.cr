module Netbox
  class API::ManufacturersBase < API::EntityWSlugAndURL; end

  class API::DeviceTypesBase < API::EntityExtended
    manufacturer : API::ManufacturersBase
    model : String
  end
end
