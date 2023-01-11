module Netbox
  class API::IPsBase
    include JSON::Serializable
    property display : String
    property family : Int32
    property address : String
  end
end
