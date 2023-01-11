require "log"
module NBXTool::Log
  FLD_DELIM = " | "
  INDENT_FOR_MULTILINE = "\n" + " " * 34 + " -> "
  LOG_FMT = ::Log::Formatter.new do |line, io|
    io << line.timestamp.to_s("%H:%M:%S (%Y-%m-%d)") << FLD_DELIM << sprintf("%-6s", line.severity) << FLD_DELIM
    line.message.split("\n").each_with_index do |l, i|
      if i > 0
        io << INDENT_FOR_MULTILINE << l
      else
        io << l
      end
    end    
  end  
  
  def self.configure(log_level : ::Log::Severity)
    ::Log.setup do |c|
      log_back = ::Log::IOBackend.new(STDERR, formatter: LOG_FMT)
      c.bind "*", log_level, log_back
    end
  end
end
