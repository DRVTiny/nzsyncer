require "openssl"
require "zabipi"
require "json"
require "log"
require "../../tool/json.cr"
require "./hostgroups.cr"
require "./hosts.cr"
require "./nbxtgroups.cr"
require "../app/config_reader.cr"
require "../../tool/logging.cr"
require "../../tool/normalize.cr"
require "./history_items.cr"

module Zabbix
  class Archivarius
    alias ValuesHistory = Zabbix::HistoryRecords(Float64) | Zabbix::HistoryRecords(UInt64) | Zabbix::HistoryRecords(String)
    alias ItemID = UInt64
    
    TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
    DELAY_SFX = {
      "h" => 3600,
      "m" => 60,
      "s" => 1,
      ""  => 1
    }
    CLASS_BY_VT = {
      0 => Float64,
      1 => String,
      2 => String,
      3 => UInt64,
      4 => String
    }
    
    Log = ::Log.for("Zabbix::Archivarius")
    NBXTool::Log.configure(:info)
    
    @config     : YAML::Any
    @debug_zapi : Bool
    @api_url    : String
    @zapi       : Monitoring::Zabipi
    
    def initialize(config_path = "./conf/nbx.yaml", zabbix_instance = "prod", @debug_zapi = false)
      @config = NZSyncer::ConfigReader.new(config_path)["zabbix"][zabbix_instance]
      @api_url = @config["url"].as_s
      @zapi =
      begin
        Monitoring::Zabipi.new(
          @api_url, @config["login"].as_s, @config["password"].as_s,
          debug: @debug_zapi, verify_cert: false, url_auto_adjust: false
        )
      rescue ex : Monitoring::HTTPException
        Log.fatal { ex.message }
        exit 1
      end
    end
    
    def get_history(itemids : Array(UInt64), from_time : Time, to_time : Time)    
      raise "itemids can not be empty" if itemids.empty?
    
      ts_now = Time.local.to_unix
    

      from_time_ts = from_time.to_unix
      to_time_ts = to_time.to_unix
      cnt_fibers = 0
    
      ch_res = Channel(Hash(UInt64, ValuesHistory)).new
      delay_by_itemid = {} of ItemID => Int64
      
      @zapi.req(
        "item.get", {
          "itemids" =>  itemids, #zapi.req("item.get", {hostids: [10816], output: %w[itemid]}).as_a.map{|ii| ii["itemid"] },
          "output"  => %w[value_type delay itemid]
        }
      ).as_a.each_with_object({} of Int32 => Array(ItemID)) do |item, by_vt|
        vt = item["value_type"].to_i64!.to_i
        itemid = item["itemid"].to_u64!.as(ItemID)
        delay_by_itemid[itemid] = self.class.delay_to_seconds(item["delay"])
        raise "Unknown value_type=#{vt}" unless CLASS_BY_VT[vt]?
        by_vt[vt]? || (by_vt[vt] = [] of ItemID)
        by_vt[vt] << itemid
  #      puts "vt=#{vt}, itemid=#{itemid}"
      end.each do |vt, ii|
        cls = CLASS_BY_VT[vt]
        spawn do
          {% begin %}
          hist_recs = {} of ItemID => ValuesHistory
          begin
            @zapi.req(
              "history.get",
              {
                "itemids"   =>  ii,
                "history"   =>  vt,
                "time_from" =>  from_time_ts,
                "time_till" =>  to_time_ts,
                "sortfield" => "clock",
                "output"    => %w[itemid clock value],
              },
              http_client: get_http_client
            ).as_a.each do |jhr|

              case cls
                {% for c in [Float64, UInt64, String] %}
                when {{c.id}}.class
                  zhr = Zabbix::HistoryItem({{c.id}}).new(jhr)
                  itemid = zhr.itemid.as(ItemID)
                  unless hist_recs.has_key?(itemid)
                    hist_recs[itemid] =  Zabbix::HistoryRecords({{c.id}}).new(delay: delay_by_itemid[itemid])
                  end
                  hist_recs[itemid].as(Zabbix::HistoryRecords({{c.id}})) << zhr
                {% end %}
              end
              
            end # <- zapi.req
          rescue e : Monitoring::HTTPException
            Log.fatal { "Monitoring::HTTPException: #{e.to_s}" }
            exit 1
          end
          
          ch_res.send(hist_recs)
          {% end %}
        end
        
        cnt_fibers += 1
      end
      
      res = {} of ItemID => ValuesHistory
      cnt_fibers.times do
        res.merge!(ch_res.receive)
      end
      
      return {
        period: {
          from: from_time_ts,
          till: to_time_ts
        },
        data: res
      }
    end
  
    def get_http_client
      tls_ctx = OpenSSL::SSL::Context::Client.new
      tls_ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      HTTP::Client.new( @api_url =~ /^(?i:https?:\/\/)/ ? URI.parse(@api_url) : @api_url, tls: tls_ctx )
    end
    
    def self.delay_to_seconds(delay : JSON::Any)
      case delay.raw
      when String
        s = delay.as_s
        if s =~ /^\s*(\d+)((?:[mhs])?)\s*$/
          $1.to_i64 * DELAY_SFX[$2]
        else
          raise "Invalid/unknown delay format: >>#{s}<<"
        end
      when Int64
        delay.as_i.to_i64
      else
        raise "Dont know how to deal with delay of #{delay.raw.class} class"
      end
    end
  end
end
