require "json"
require "../zabbix/hosts"
require "./zbxtenant"
class NZSyncer::ZHostsDump
    include JSON::Serializable
    
    property by_name :    Hash(String, Zabbix::Host)
    property by_addr :    Hash(String, Zabbix::Host)
    property by_tenant :  Hash(String, NZSyncer::ZBXTenant)
end
