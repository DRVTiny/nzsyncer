require "../../tool/logging"
require "zabipi"
require "../../tool/json"
require "../netbox/api.cr"
require "./*"
class Netbox::API::HostsCommon
  HOST_TAG_ORPHANED = "netbox-synced-orphaned"
  HOST_STATUS_ACTIVE = "active"
  HOST_IS_ACT_CHECKS = {
    has_ipv4_address: ->(h : Netbox::API::HostsCommon) : Bool {
        h.primary_ip4 ? true : false
      },
    status_is_active: ->(h : Netbox::API::HostsCommon) : Bool {
        h.status.value == HOST_STATUS_ACTIVE
      },
    name_suitable_for_prod: ->(h : Netbox::API::HostsCommon) : Bool {
        h.host_name_for(:prod) ? true : false
      },
    not_orphaned: ->(h : Netbox::API::HostsCommon) : Bool {
        (h.tags.try &.index {|e| e.slug == HOST_TAG_ORPHANED }) ? false : true
      },
  }
  
  def check(*checks)
    checks.each do |chk|
      
      chk_res = if chk.is_a?(Proc)
        chk.call(self)
      elsif chk.is_a?(Symbol)
        if chk_proc = HOST_IS_ACT_CHECKS[chk]?
          chk_proc.call(self)
        else
          raise "No such host check: #{chk}"
        end
      else
        raise "Unknown host check type/class: #{chk.class}"
      end
      
      return false unless chk_res
    end
    true
  end
end

class NZSyncer  
  VERSION = "0.1.4"
  RX_NBX_COMMENT_IN_ZBX = /(?:^|\n)\s*Netbox ->(.+?)<- Netbox\s*(?:\n|$)/m
  FMT_INS_TO_HOST_DESCR = "Netbox ->\n%s\n<- Netbox"
  class NZError < ::Exception; end
  
  Log = ::Log.for("NZSyncer")

  getter zapi : ::Monitoring::Zabipi
  getter nbx : Netbox::API
  getter zabbix_id : String
  property zhosts : ZHostsDump
  property tenants : Hash(String, NBXTenant)
  property nbx_hosts : Hash(String, Netbox::API::HostsCommon)

  def initialize(config_file_path : String, zabbix_id : String | Symbol)
    conf = ConfigReader.new(config_file_path)
    @zabbix_id = zabbix_id.is_a?(Symbol) ? zabbix_id.to_s : zabbix_id
    netbox_url = conf["connection"]["type"].as_s + "://" + conf["connection"]["server"].as_s + "/api"
    @nbx = ::Netbox::API.new(
      netbox_url,
      conf["api"]["token"].as_s,
      debug: conf.debug?
    )
    
    unless zconf = conf["zabbix"][@zabbix_id]?
      raise NZError.new("No such zabbix id defined: #{@zabbix_id}")
    end
    
    @zapi =
      begin
        ::Monitoring::Zabipi.new(
          zconf["url"].as_s,
          zconf["login"].as_s,
          zconf["password"].as_s,
          debug: ConfigReader.debug?(zconf["debug"]?.try &.as_s || "false"),
          verify_cert: false,
          url_auto_adjust: false
        )
      rescue ex : Exception
        Log.fatal { "Failed to create Zabbix API connector: #{ex.message}" }
        exit 1
      end
      
    @tenants, @nbx_hosts = get_nbx_tenants
    @zhosts = ZHostsDump.from_json( 
      File.read zconf["hosts_dump"].as_s
    )
  end
  
#  def initialize(conf : ConfigReader, @tenants : Hash(String, NBXTenant))
#  end
  
  def create_tenant_zgroup(nbxt : NBXTenant)
    zg_name = nbxt.zbx_name

    # Zabbix API call ->
    groupid = NBXTools::JSON.to_i64!(
      @zapi.do("hostgroup.create", {"name" => zg_name})
        .result["groupids"][0]
    )
    # <- Zabbix API call

    norm_ten_name = nbxt.text_id.not_nil!
    zhosts.by_tenant[norm_ten_name] =
      ZBXTenant.new(
        groupid, zg_name, norm_ten_name, nbx_ten_name: nbxt.name
      )
  end

  def create_tenant_zgroup(norm_ten_name : String)
    unless nbxt = @tenants[norm_ten_name]?
      raise NZError.new("Could not create_tenant_zgroup: no such tenant <<#{norm_ten_name}>> found in Netbox")
    end

    create_tenant_zgroup(nbxt) # return ZBXTenant
  end

  def add_hosts_to_zgroup(groupid : Int64, hostids : Array(Int64))
    @zapi.do(
      "hostgroup.massadd",
      {
        groups: {groupid: groupid},
        hosts:  hostids.map { |hostid| {hostid: hostid} },
      }
    ).result ? true : false
  end
  
  def update_hosts(upd_recs)
    Log.info { "will update hosts comments: <<" + upd_recs.to_json + ">>"}
    zapi.req("host.update", 
      upd_recs.map do |hostid, descr|
        {"hostid" => hostid, "description" => descr}
      end
    )    
  end
  
  def sync_zabbix_with_netbox(nbxt : NBXTenant, zbxt : ZBXTenant)
    zg_name = nbxt.zbx_name
    upd_hosts_descr = Hash(Int64, String).new
        
    hostids = nbxt.hosts.each_with_object([] of Int64) do |host_name, ids|
      if zhost = @zhosts.by_name[host_name]?
        unless zbxt.hosts.includes? host_name
          Log.warn { "We are going to add host #{host_name} to Zabbix group #{zg_name}" }
          ids << zhost.hostid
          zbxt.hosts.add(host_name)
        end
        
        if nbx_host = @nbx_hosts[host_name]?
          zdescr = zhost.description || ""
          ncomms = nbx_host.comments
          upd_host_comm : String? =  nil
          
          if zdescr =~ RX_NBX_COMMENT_IN_ZBX
            zcomms = $1.gsub(/(?:^\n+|\n+$)/, "")
            unless zcomms == ncomms
              upd_host_comm = zdescr.gsub(RX_NBX_COMMENT_IN_ZBX, ncomms.size > 0 ? sprintf(FMT_INS_TO_HOST_DESCR, ncomms) : "")
            end
          elsif ncomms.size > 0
            upd_host_comm = zdescr + (zdescr =~ /\n$/m ? "" : "\n") + sprintf(FMT_INS_TO_HOST_DESCR, ncomms)
          end
          upd_hosts_descr[zhost.hostid] = upd_host_comm if upd_host_comm
        else
          raise "Host #{host_name} was mentioned in Netbox tenant <<#{nbxt.name}>>, but is absent in nbx_hosts registry. By design, it is very strange/rare case!"
        end
      else
        Log.error { "Host was mentioned in Netbox tenant <<#{nbxt.name}>>, but not found in Zabbix[#{@zabbix_id}]: #{host_name}" }
      end
    end # <- hostids
    
    unless upd_hosts_descr.empty?
      update_hosts(upd_hosts_descr)
    end
    
    if hostids.size > 0
      add_hosts_to_zgroup(zbxt.groupid, hostids)
    else
      Log.info { "No hosts to be added to Zabbix group #{zbxt.name} from Netbox tenant <<#{nbxt.name}>>" }
      false
    end

    zg_hostids2remove = (zbxt.hosts - nbxt.hosts).map do |host_name|
      Log.warn { "Host #{host_name} present in Zabbix group <<#{zg_name}>>, but is absent in the corresponding Netbox tenant <<#{nbxt.name}>>" }
      @zhosts.by_name[host_name].hostid
    end
  end

  def sync_zabbix_with_netbox(nbxt : NBXTenant)
    unless zbxt = zhosts.by_tenant[nbxt.text_id.not_nil!]?
      raise NZError.new("sync_zabbix_with_netbox: No such Zabbix host group found: #{nbxt.zbx_name}")
    end

    sync_zabbix_with_netbox(nbxt, zbxt)
  end
  
  def sync_zabbix_with_netbox
    sprintf_fmt = "==========> PROCESSING NETBOX TENANT: %s [%s]  <=========="
    @tenants.each do |norm_ten_name, nbxt|
      nbx_ten_name = nbxt.name
      Log.info { sprintf(sprintf_fmt, nbx_ten_name, norm_ten_name) }
      
      unless zbxt = @zhosts.by_tenant[norm_ten_name]?
        Log.info { "No hostgroup for tenant <<#{nbx_ten_name}>> found in Zabbix, trying to create it..." }
        begin
          zbxt = create_tenant_zgroup(nbxt)
        rescue ex : Exception
          Log.error { "Failed to create zabbix group <<#{nbxt.zbx_name}>>: '#{ex.message}', we have to skip this tenant" }
          next
        end
        Log.info { "OK, Zabbix group was created as <<#{zbxt.name}>> with groupid=#{zbxt.groupid}" }
      end
      
      sync_zabbix_with_netbox(nbxt, zbxt.not_nil!)
    end # <- iterate @tenants
  end
  
  private def get_nbx_tenants
    #           		               ten_name           host_name    nbx_host_inst
    host_chans = [] of Channel(Tuple(String, Array(Tuple(String, Netbox::API::HostsCommon))))
    tens = @nbx.get_entities(:tenants).as(Array(Netbox::API::Tenants))
    nbx_tenants = Hash(String, NBXTenant).new
    tens.each do |ten|
      next unless ten.slug =~ /-(?:prod|uat)/
      next unless nbx_ten_name = ten.name || ten.display
      #    next unless norm_ten_name = NBXTools::Normalize.tenant_name_for(ten_name, :netbox)
      nbxt = NBXTenant.new(nbx_ten_name)
      next unless norm_ten_name = nbxt.text_id
      nbx_tenants[norm_ten_name] = nbxt
      {:virtual_machines, :hosts}.each do |hosts_type|
        host_chans.push(ch_res = Channel(Tuple(String, Array(Tuple(String, Netbox::API::HostsCommon)))).new(1))
        spawn do
          hosts = nbx
            .get_hosts(hosts_type, tenant: ten.slug)
            .each_with_object([] of Tuple(String, Netbox::API::HostsCommon)) do |h, l|
              # puts "host: #{h.host_name} name4prod: #{h.host_name_for(:prod)} name: #{h.name} display: #{h.name}"
              unless h.check(:has_ipv4_address, :status_is_active, :name_suitable_for_prod, :not_orphaned)
                # Log.warn { sprintf("host <<%s>> not suitable for tenant %s", h.host_name || "UNKNOWN", ten.slug) }
                # if name =~ /(?i:khp-hs-db01)/
                # if ! h.primary_ip4
                # puts "because of h.primary_ip4"
                # elsif h.status.value != "active"
                # puts "because of status <<#{h.status.value}>>"
                # else
                # puts "because of host_name <<#{host_name}>>"
                # end
                # pp h if h.host_name =~ /(?i:khp-ncb-db)/

                # end
                next
              end
              l << {h.host_name_for(:prod).not_nil!, h}
            end
          ch_res.send({norm_ten_name, hosts})
        end
      end # <- each hosts_type
    end   # <- each netbox_tenant
    
    nbx_hosts = {} of String => Netbox::API::HostsCommon
    host_chans.each do |ch|
      norm_ten_name, hosts = ch.receive
      hosts.each do |host_name, nbx_host|
        nbx_tenants[norm_ten_name].hosts.add(host_name)
        nbx_hosts[host_name] = nbx_host
      end
    end

    {nbx_tenants, nbx_hosts}
  end
end
