require "json"
module Zabbix
  class HostsDump
    include JSON::Serializable
    
    property by_name : Hash(String, Zabbix::Host)
    property by_addr : Hash(String, Zabbix::Host)
    property by_tenant : Hash(String, Zabbix::NBXTGroup)
  end
end
