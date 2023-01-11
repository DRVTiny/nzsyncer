require "yaml"

class NZSyncer
  class ConfigReader
    @config : YAML::Any
    @config_path : Path
    RX_BOOL = [
      {/^(?i:t(rue)?|y(?:es)?|1)$/, true},
      {/^(?i:f(?:alse)?|no?|0)$/, false},
    ]

    def initialize(config_path : (Path | String))
      @config_path = (config_path.is_a?(String) ? Path.new(config_path) : config_path).normalize
      unless File.exists?(@config_path) && File.readable?(@config_path)
        raise "you must specify path to the existing (and readable) configuration file"
      end

      @config = YAML.parse(File.read(@config_path))
    end

    def [](par : String | Symbol)
      if v = @config[par.is_a?(String) ? par : par.to_s]?
        return v
      else
        raise "no such top-level configuration parameter: #{par}"
      end
    end

    def []?(par : String | Symbol)
      @config[par.is_a?(String) ? par : par.to_s]?
    end

    def debug?
      self.class.debug? @config["debug"]?
    end
    
    def self.debug?(some_s : String | YAML::Any | Nil) : Bool
      return false unless some_s
      s = some_s.is_a?(YAML::Any) ? some_s.as_s : some_s
      RX_BOOL.each do |rx, fl|
        return fl if s =~ rx
      end
      raise "failed to parse as boolean, unknown value: #{s}"
    end
  end
end # <- NZSyncer::ConfigReader
