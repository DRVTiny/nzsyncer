module Netbox
  class API::Location < API::EntityWSlugAndURL
    @[JSON::Field(key: "_depth")]
    property depth : Int32
  end
end
