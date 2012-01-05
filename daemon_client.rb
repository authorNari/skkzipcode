#!/usr/bin/ruby -wKU

require 'socket'
require 'optparse'
require 'benchmark'

@client = 1
@request = 1500
@client = 100 if $DEBUG
@request = 1000 if $DEBUG
opt = OptionParser.new
opt.on("-c CNT", "--client CNT", Integer) {|c| @client = c}
opt.on("-r CNT", "--request CNT", Integer) {|c| @request = c}
opt.parse!(ARGV)

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
  @request.times { res << codes[(rand * codes.size).to_i] }
  res
end

list = input_zipcodes(File.join(File.dirname(__FILE__), "SKK-JISYO.zipcode"))
list = ARGV unless ARGV.size.zero?

process_ids = []
@client.times do
  process_ids << fork do
    $stderr = $stdout = File.open("/tmp/skk_exelog_#{$$}", "w")
    Benchmark.bm do |x|
      t = x.report("request_time:") do
        list.each do |e|
          s = TCPSocket.new("localhost", 12345)
          s.puts(e)
          while s.gets
            puts $_
          end
          s.close
        end
      end
      open("/tmp/skk_reqsec_#{$$}", "w") {|f| f.write "request/sec:#{(t/@request).to_s}" }
    end
    exit!
  end
end

Process.waitall
cat_command = "cat "
process_ids.each{|id| cat_command << " /tmp/skk_exelog_#{id} /tmp/skk_reqsec_#{id} " }
cat_command << " > /tmp/skk_exelog"
exec cat_command
exec "rm -f /tmp/skk_exelog_*"
