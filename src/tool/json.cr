require "json"

struct JSON::Any
  def to_i64!
    if i = as_i64?
      i
    elsif s = as_s?
      s.to_i64
    else
      raise "Failed to convert JSON::Any value <<#{@raw}>> to Int64"
    end
  end

  def to_u64!
    if i = as_i64?
      i.to_u64
    elsif s = as_s?
      s.to_u64
    else
      raise "Failed to convert JSON::Any value <<#{@raw}>> to UInt64"
    end
  end
end

module NBXTools::JSON
  class AutoInt64
    def self.from_json(value : JSON::PullParser) : Int64
      case value.kind
      when .float?
        value.read_float
      when .int?
        value.read_int
      when .string?
        value.read_string
      else
        value.raise("Failed to autoconvert #{value.kind} to Int64")
      end.to_i64
    end
   
    def to_json(value : Float64, json : JSON::Builder) : Nil
      value.to_json(json)
    end
  end
  
  def self.to_i64!(v : ::JSON::Any) : Int64
    v.to_i64!
  end
end
