require "json"
module Zabbix
  enum HistoryItemType
    FLOAT64
    CHAR
    LOG
    UINT
    TEXT
  end
  
  class HistoryItem(T)
    include JSON::Serializable
    
    property clock : Time
    property value : T
    property itemid : UInt64
    property ns : Int64
    def initialize(itemid, @value : T, clock : Int64 | Time, @ns = 0_i64)
      @itemid = itemid.is_a?(UInt64) ? itemid : itemid.to_u64
      @clock = if clock.is_a?(Int64)
                 Time.unix(clock)
               else
                 clock
               end 
    end
    
    def initialize(j : JSON::Any)
      @itemid = j["itemid"].as_s.to_u64
      @clock  = Time.unix(j["clock"].as_s.to_i64)
      @value =
      {% if T == Float64 %}
        j["value"].as_s.to_f64
      {% elsif T == String %}
         j["value"].as_s
      {% else %}
        j["value"].as_s.to_u64
      {% end %}
      @ns = j["ns"]?.try &.as_s.to_i64 || 0_i64
    end
  end # <- class HistoryItem(T)
  
  class HistoryRecords(T)
    include JSON::Serializable
    DFLT_ZBX_DELAY = 60
    
    @[JSON::Field(converter: JSON::ArrayConverter(Time::EpochConverter))]
    property clocks : Array(Time)
    
    getter values : Array(T)
    getter delay : Int64
    
    def initialize(@delay = DFLT_ZBX_DELAY, @clocks = [] of Time, @values = [] of T)
      unless @clocks.size == @values.size
        raise %q[Size of "clocks" and "values" vectors must be the same]
      end
    end
    
    def <<(hi : HistoryItem(T))
      @clocks << hi.clock
      @values << hi.value
    end
    
    def each(& : (Time, T) ->)
      @clocks.each_with_index do |clock, i|
        yield(clock, @values[i])
      end
    end
  end # <- class HistoryRecords(T)
end
