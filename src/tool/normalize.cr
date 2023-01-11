module NBXTools::Normalize
  	RXS_BEGIN = %q[^\s*]
  	RXS_END = %q[\s*$]
  	RXS_ZGROUP_NAMES_PFX = %q<NBXT\s*/\s*>
  	RXS_TENANT_NAME_BASE = %q<(.+?)(?:\s+|\s*-\s*)((?i:UAT|PROD))>
    RX_TENANT_NAME_FOR = {
      zabbix: Regex.new(RXS_BEGIN + RXS_ZGROUP_NAMES_PFX + RXS_TENANT_NAME_BASE + RXS_END),
      netbox: Regex.new(RXS_BEGIN +                        RXS_TENANT_NAME_BASE + RXS_END),
    }
    RX_HOST_NAME_IN = {
      prod: /^((?i:[ks][hv][ptudam]-[^.]+))((?:\..+)?)$/
    }
    
    def self.tenant_name_for(ten_name : String, what=:zabbix) : String?
      if rx = RX_TENANT_NAME_FOR[what]?
        if ten_name =~ rx
          ($1.gsub(/\s+/, "") + "-" + $2).upcase
        else
          nil
        end
      else
        raise "unknown inventory information source specified: #{what}"
      end
    end
    
    def self.host_name_for(what_as = :prod, *try_names)
      unless rx_name = RX_HOST_NAME_IN[what_as]?
        raise "unknown AS name given: #{what_as}"
      end
      
      return nil unless a0 = try_names[0]?
      
      (a0.is_a?(Enumerable) ? a0 : try_names).each do |psbl_name|
        return $1.downcase if psbl_name =~ rx_name
      end
      
      nil
    end    
end

module Zabbix
  class Host
    def appropriate_name_for(what_as)
      NBXTools::Normalize.host_name_for(what_as, @uniq_names)
    end
  end
end

module Netbox
  class API::HostsCommon
    @[JSON::Field(key: "host_name_for", ignore: true)]
    getter host_name_for : Hash(Symbol, String?)? = nil  
    
    def host_name_for(what_as)
      if hnf = @host_name_for
        if hnf.has_key?(what_as)
          return hnf[what_as]
        end
      else
        @host_name_for = {} of Symbol => String?
      end
      host_name = NBXTools::Normalize.host_name_for(what_as, @name, @display)
      if hnf = @host_name_for
        hnf[what_as] = host_name
      end
      host_name
    end
  end
end
