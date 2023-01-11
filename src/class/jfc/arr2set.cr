module JFC
    class Arr2SetConv
      def self.from_json(jpp : JSON::PullParser) : Set(String)
        s = Set(String).new
        jpp.read_array do
          s << jpp.read_string
        end
        s
      end
    end
end