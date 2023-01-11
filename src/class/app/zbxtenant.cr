require "../zabbix/hostgroups.cr"

class NZSyncer::ZBXTenant < Zabbix::HostGroup
    property hosts : Set(String)
    property norm_ten_name : String
    property nbx_ten_name : String?

    def initialize(
      @groupid,
      @name,
      @norm_ten_name,
      @hosts = Set(String).new,
      @nbx_ten_name = nil
    ); end
end
