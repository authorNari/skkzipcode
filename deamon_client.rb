require 'socket'

def input_zipcodes(filepath)
  codes = []
  open(filepath) do |f|
    f.each_line do |l|
      if /(\d+)\s\/(.+)\// =~ l
        codes << $1
      end
    end
  end
  res = []
  1000.times { res << codes[(rand * codes.size).to_i] }
  res
end

list = input_zipcodes(File.join(File.dirname(__FILE__), "SKK-JISYO.zipcode"))
list = ARGV unless ARGV.size.zero?

list.each do |e|
  s = TCPSocket.new("localhost", 12345)
  s.puts(e)
  while s.gets
    puts $_
  end
  s.close
end
