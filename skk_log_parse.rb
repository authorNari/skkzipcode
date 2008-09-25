#!/usr/bin/ruby -wKU

path = ARGV[0]

def parse(str)
  process_id = nil
  dump = {:memory_stats => {}, :request_secs => []}
  str.each_line do |l|
    dump[:request_secs] << $1.to_f if /request\/sec:.+\(\s+(\d+\.\d+)\)/ =~ l
    if /Process id\s+(\d+)/ =~ l
      process_id = $1.to_i
      dump[:memory_stats][process_id] ||= {:rss => 0, :shared => 0, :private => 0}
    end
    if process_id
      %w(rss shared private).each do |n|
        cap_n = n.capitalize
        if /\A#{cap_n}\s+(\d+)/ =~ l
          dump[:memory_stats][process_id][n.to_sym] = $1.to_i if dump[:memory_stats][process_id][n.to_sym] < $1.to_i
        end
      end
      process_id = nil if l.include? "gc count"
    end
  end
  dump
end

def report(data)
  mem_shared_ave = 0.0
  mem_priv_ave = 0.0
  mem_shared_total = 0
  mem_priv_total = 0
  req_par_sec = 0.0

  data[:memory_stats].values.each do |stats|
    mem_priv_total += stats[:private]
    mem_shared_total += stats[:shared]
  end
  mem_priv_ave = mem_priv_total.to_f/data[:memory_stats].size
  mem_shared_ave = mem_shared_total.to_f/data[:memory_stats].size

  total = 0.0
  data[:request_secs].each {|s| total += s }
  req_par_sec = total/data[:request_secs].size

  puts <<EOS
USE_MEM     : #{mem_priv_total}\tkb
SHARED_AVE  : #{mem_shared_ave}\tkb
PRIV_AVE    : #{mem_priv_ave}\tkb
REQ/SEC     : #{req_par_sec}
EOS
end

open(path){|f| report(parse(f.read)) }
