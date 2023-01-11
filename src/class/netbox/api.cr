require "json"
require "halite"
require "openssl"

module Netbox
  class API; end
end

require "./api/result"

module Netbox
  class API

    getter url, token
    @tls : OpenSSL::SSL::Context::Client

    def initialize(@url : String, @token : String, @debug = false)
      @token = "Token " + @token
      @tls = OpenSSL::SSL::Context::Client.new
      @tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE
    end

#    def get_tenants
#      results = [] of API::Tenants
#      get_smth("/tenancy/tenants/").each do |ch_res|
#        if (ar = ch_res.receive.results).is_a?(Array(API::Tenants))
#          results.concat(ar)
#        end
#      end
#      results
#    end
    
    
#    def get_vms_in_tenant(tenant)
#      results = [] of API::VirtualMachines
#      get_smth("/virtualization/virtual-machines/", tenant: tenant).each do |ch_res|
#        if (ar = ch_res.receive.results).is_a?(Array(API::VirtualMachines))
#          results.concat(ar)
#        end
#      end
#      results
#    end
#
#    def get_hosts_in_tenant(tenant)
#      results = [] of API::Hosts
#      get_smth("/api/dcim/devices/", tenant: tenant).each do |ch_res|
#        if (ar = ch_res.receive.results).is_a?(Array(API::Hosts))
#          results.concat(ar)
#        end
#      end
#      results
#    end
    {% begin %}
    {% 
      how2deal_with = {
        virtual_machines:  {"/virtualization/virtual-machines/",  Array(API::VirtualMachines)},
        hosts:             {"/dcim/devices/",                     Array(API::Hosts)},
        tenants:           {"/tenancy/tenants/",                  Array(API::Tenants)}
      }        
    %}
    {% for k, v in how2deal_with %}
    {%   tgt_class = v[1].id %}
      def get_netbox_{{k.id}}(**params)
        results = {{tgt_class}}.new
        nxt = {{v[0]}}
        fl_first = true
        loop do
          res, nxt = if fl_first
                       fl_first = false 
                       get_api_results(nxt, **params)
                     else
                       get_api_results(nxt)
                     end
                     
          break unless res.size > 0
          
          if res.is_a?({{tgt_class}})
            results.concat(res.as({{tgt_class}}))
          else
            pp res
            raise "^^^^^^ got results of #{res.class} class when trying to get {{k.id}} which native class is {{tgt_class.id}}"
          end
          
          break unless nxt
          puts "nxt=#{nxt}" if @debug
        end
        results
      end
    {% end %}
    
    def get_entities(what : Symbol, **params)
      case what
      {% for k, v in how2deal_with %}
        when :{{k.id}}
          get_netbox_{{k.id}}(**params)
      {% end %}
      else
        raise "dont know, how to deal with #{what} :("
      end
    end
    
    def get_hosts(hosts_type : Symbol, **params) : Array(API::HostsCommon)
      get_entities(hosts_type, **params).unsafe_as(Array(API::HostsCommon))
    end
    {% end %}
    private def get_api_results(api_url : String, **params)
      req_url = if api_url =~ /^(?i:https?:\/\/)/ 
                  api_url.gsub(/http:/, "https:")
                else 
                  @url + api_url
                end
      puts "request url: #{req_url} params: #{params}" if @debug
      
      json_resp = Halite.get(
        req_url,
        headers: {
          "Authorization" => @token,
          "Accept"        => "application/json",
        },
        params: params,
        tls: @tls
      ).body.gsub('\n', ' ').gsub('\r', ' ').gsub(%q(,"vcpus":), %q(,"type": "vm","vcpus":)).gsub(%q(,"rack":), %q(,"type": "host","rack":))

#      puts "result=#{json_resp}" if @debug
      
#      res : API::Result
      
      begin
        res = API::Result.from_json(json_resp)
        puts "Count of results: #{res.results.size}" if @debug
        if res.results.size == 0
          puts "We have this: JSON>>> #{json_resp} <<<JSON\nBut it seems that no results was parsed!" if @debug
#          exit 1
         end
      rescue json_ex : JSON::ParseException
        puts "Error while trying to parse (JSON?) answer from Netbox API: #{json_ex.message}. JSON itself: <<#{json_resp}>>"
        exit(1)
      end
      
      return {res.results, res.next}
    end # <- method
  end # <- class
end # < module

