require "../../tool/normalize"
class NZSyncer::NBXTenant
    RX_ZIBIFI        = /(?:\s*-)?\s*(UAT|PROD)\s*$/
    ZGROUP_NAMES_PFX = "NBXT/"

    property name : String
    property text_id : String?
    property zbx_name : String
    property hosts : Set(String)

    def initialize(@name, zbx_name = nil, @hosts = Set(String).new)
      @text_id = NBXTools::Normalize.tenant_name_for(@name, :netbox)
      @zbx_name = zbx_name || ZGROUP_NAMES_PFX + @name.gsub(RX_ZIBIFI, " - \\1")
    end
end
