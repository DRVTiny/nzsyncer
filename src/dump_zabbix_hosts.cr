require "zabipi"
require "json"
require "log"
require "./tool/json.cr"
require "./class/zabbix/hostgroups.cr"
require "./class/zabbix/hosts.cr"
require "./class/zabbix/nbxtgroups.cr"
require "./class/config_reader.cr"
require "./tool/logging.cr"
require "./tool/normalize.cr"

module Netbox
    FL_PRINT_HOSTS = false
    
    Log = ::Log.for("Netbox")
    
    NBXTool::Log.configure(:info)
    conf = ConfigReader.new("./conf/nbx.yaml")
    prod_conf = conf["zabbix"]["prod"]
    
    def self.get_os_templates(zapi) : Array(Int64)
      %w(Linux Windows).map do |os_type|
          zapi.do(
            "template.get",
            {
              "search" => {"name" => "Template OS #{os_type}*"},
              "searchWildcardsEnabled" => true,
              "tags" => [{"tag" => "type", "value" => "BASIC_OS_BY_AGENT", "operator" => 0}],
              "output" => ["name"]
            }
          )
          .result.as_a
          .map {|tmpl| NBXTools::JSON.to_i64!(tmpl["templateid"]) }
      end.flatten
    end
    
    def self.process_nbxt_groups(zapi)
      rx_zg_name = NBXTools::Normalize::RX_TENANT_NAME_FOR[:zabbix]
      nbxt_groups = Hash(String, Zabbix::NBXTGroup).new
      to_rename = zapi.do("hostgroup.get", {
        "search" => {"name" => "NBXT/*"},
        "searchWildcardsEnabled" => true,
        "output" => ["name"]
      }).result.as_a.each_with_object([] of NamedTuple(groupid: Int64, name: String)) do |zg, ren|
        zg_name = zg["name"].as_s
        unless zg_name =~ rx_zg_name
          Log.fatal { %Q<ERROR: Strange/abnormal Zabbix NBXT/ group name: #{zg_name}> }
          exit 1
        end
        
        zg_name_must_be = "NBXT/" + $1 + " - " + $2.upcase
        
        if nbxt_groups[zg_name_must_be]?
          Log.error { "Zabbix group <<#{zg_name}>> is a duplicate for <<#{zg_name_must_be}>>. Please, remove one of them and retry" }
          exit 1
        end
        
        unless norm_ten_name = NBXTools::Normalize.tenant_name_for(zg_name_must_be, :zabbix)
          Log.error { "Failed to get normalized version for Zabbix group #{zg_name}" }
          exit 1
        end
        
        groupid = NBXTools::JSON.to_i64! zg["groupid"]
        
        unless zg_name == zg_name_must_be
          Log.warn { "Zabbix group name <<#{zg_name}>> was wrong-formatted, will be renamed to <<#{zg_name}>>" }
          ren << {groupid: groupid, name: zg_name_must_be}
        end
        
        nbxt_groups[norm_ten_name] = Zabbix::NBXTGroup.new(
          groupid: groupid,
          name: zg_name_must_be,
          norm_ten_name: norm_ten_name,
          hosts: Set(String).new
        )
      end
      
      if to_rename.size > 0
        pp zapi.do("hostgroup.update", to_rename).result
      end
      
      nbxt_groups
    end
    
    zapi =
    begin
      Monitoring::Zabipi.new(prod_conf["url"].as_s, prod_conf["login"].as_s, prod_conf["password"].as_s, debug: true, verify_cert: false, url_auto_adjust: false)
    rescue ex : Monitoring::HTTPException
      Log.fatal { ex.message }
      exit 1
    end
    
    tens_zhosts = process_nbxt_groups zapi
    
    hosts = zapi.do(
      "host.get",
      {
        "templateids" => get_os_templates(zapi),
        "monitored_hosts" => 1,
        "output" => ["host", "name", "description"],
        "selectInterfaces" => ["dns", "ip", "useip"],
        "selectGroups" => ["name"]
      }
    )
    .result.as_a
    .map { |zhost| Zabbix::Host.new(zhost) }
    
    # zp_host_by_name
    # zp_host_by_ip
    if FL_PRINT_HOSTS
        puts (
          hosts.map do |h|
            {h.tech_name, h.display_name, h.domain_names[0]? || "NO_DNS", h.ip_addrs[0]? || "NO IP"}.join("\t")                    
          end.join("\n")
        )
    end
    
    zp_host = {} of String => Hash(String, Zabbix::Host)
    {"by_name", "by_addr"}.each do |by_what|
      zp_host[by_what] = {} of String => Zabbix::Host
    end
    
    pp_stderr = PrettyPrint.new(STDERR)
    STDERR.flush_on_newline = true
    hosts.each do |host|
      if (host_name = host.appropriate_name_for(:prod)) && (ip = host.first_not_local_ip)
        if zp_host["by_name"][host_name]? || zp_host["by_addr"][ip]?
          { {"by_name", host_name, "name"}, {"by_addr", ip, "ip address"} }.each do |t|
            if earlier_found_h = zp_host[t[0]][t[1]]?
              Log.error { "got yet another host with the same #{t[2]} <<#{t[1]}>>\nfound earlier: #{earlier_found_h}\nfound now: #{host}" }
            end
          end
        else
          zp_host["by_name"][host_name] = host
          zp_host["by_addr"][ip] = host
          
          host.groups.each do |host_group|
            hg_name = host_group.name
            next unless ten_name = NBXTools::Normalize.tenant_name_for(hg_name, :zabbix)
            unless zbxt = tens_zhosts[ten_name]?
              Log.fatal { "host #{host_name} associated with NBXT group <<#{hg_name}>> which was not found by initial groups search" }
              exit 1
            end
            zbxt.hosts.add(host_name)
          end
        end
      else
        Log.warn { "failed to get appropriate name or/and ip for this host: #{host}" }
      end
    end
    
    begin
        out_file = prod_conf["hosts_dump"].as_s
        {
          "by_name": zp_host["by_name"],
          "by_addr": zp_host["by_addr"],
          "by_tenant": tens_zhosts
        }.to_json(
          File.new(out_file, mode: "w")
        )
        Log.info { "hosts dump was written to #{out_file}" }
    rescue ex : Exception
      Log.fatal { "Failed to write dump file: #{ex.message}" }
    end
end
