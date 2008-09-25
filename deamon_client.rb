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

@client.times do
  fork do
    Benchmark.bm(7, "request/sec:") do |x|
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
      [t/@request]
    end
    exit!
  end
end

