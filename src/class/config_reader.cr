require "yaml"
module Netbox
  class ConfigReader
    @config : YAML::Any
    RX_BOOL = [
      {/^(?i:t(rue)?|y(?:es)?|1)$/, true},
      {/^(?i:f(?:alse)?|no?|0)$/,   false}
    ]
    
    def initialize(@config_path : String)
    
      raise "you must specify configuration file path" if @config_path.size == 0
      
      if File.readable?  @config_path
        @config = YAML.parse(File.read(@config_path))
      else
        raise "configuration file #{@config_path} not exists or not readable"
      end
    end
    
    def [](par : String)
      if v = @config[par]?
        return v
      else
        raise "no such top-level configuration parameter: #{par}"
      end
    end
    
    def []?(par : String)
      @config[par]?
    end
    
    def debug?
      if s = @config["debug"]?
        RX_BOOL.each do |rx, fl|
          return fl if s =~ rx
        end
        raise "unknown value: #{s}"
      else
        false
      end
    end
  end
  
end
