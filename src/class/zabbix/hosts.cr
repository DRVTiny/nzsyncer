require "json"
module Zabbix
  class Host
    include JSON::Serializable
    
    getter hostid : Int64
    getter tech_name : String, display_name : String
    getter ip_addrs : Array(String), domain_names : Array(String)
    getter uniq_names : Set(String), groups : Array(HostGroup)
    getter description : String?
    
    def initialize(zhost : JSON::Any)
      @hostid = NBXTools::JSON.to_i64! zhost["hostid"]
      @tech_name = zhost["host"].as_s
      @display_name = zhost["name"].as_s
      comments = zhost["description"].as_s.gsub(/^\s+/, "").gsub(/\s+$/, "")
      @description = comments.size > 0 ? comments : nil
      @ip_addrs = [] of String
      @domain_names = [] of String
      zhost["interfaces"].as_a.each do |addr|
        if (ip = addr["ip"].as_s).size > 0
          @ip_addrs << ip
        end
        if (dns = addr["dns"].as_s).size > 0
          @domain_names << dns
        end        
      end
      @uniq_names = [@tech_name, @display_name, @domain_names]
        .flatten
        .map {|n| n.downcase }
        .to_set
      @groups = zhost["groups"].as_a.map do |zgrp|
        HostGroup.new(
          groupid: NBXTools::JSON.to_i64!( zgrp["groupid"] ),
          name: zgrp["name"].as_s
        )
      end
    end
    
    def first_not_local_ip
      @ip_addrs.each do |ip|
        return ip if ip !~ /^127\./
      end
      nil
    end

    def to_s(io)
      io << "tech_name=" << @tech_name << %q[ visible_name="] << @display_name << %q[" ips=] << @ip_addrs.join(",") << " dns=" << @domain_names.join(",") << " groups=[[" << groups.map {|g| g.name }.join(", ") << "]]"
    end
    
    def to_s
      io = IO::Memory.new
      to_s(io)
      io.to_s
    end
    
    def inspect(io : IO)
      io << "ZHost{ "
      to_s(io)
      io << " }"
    end
  end 
end