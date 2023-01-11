require "json"
module Zabbix
  class HostGroup
    include JSON::Serializable
    property name : String
    property groupid : Int64
    def initialize(@groupid, @name); end
  end
end
