if $DEBUG
  # for memory profile
  def cow_dump(pid, type=:none)
    rss = 0
    shared = 0
    private = 0
    open("/proc/#{pid}/smaps") do |f|
      is_heap = false
      while f.gets
        is_heap = true if /(\d+).+\[heap\]/ === $_
        if is_heap
          case $_
          when /Rss\:\s+(\d+)/
            rss += $1.to_i
          when /(Shared_Clean|Shared_Dirty)\:\s+(\d+)/
            shared += $2.to_i
          when /Private_Clean\:\s+(\d+)/
            private += $1.to_i
          when /Private_Dirty\:\s+(\d+)/
            private += $1.to_i
            is_heap = false
          end
        end
      end
    end
    res = <<"EOS"
== #{type}
Process id #{pid}
Rss\t#{rss}\tkb
Shared\t#{shared}\tkb
Private\t#{private}\tkb
EOS
  end
end

require 'socket'

@tmp = []
def postcode_dict(filepath)
  @dict = {}
  source = ""
  open(filepath) do |f|
    source = f.read
  end
  @scan_zip = []
  source.scan(/(\d+)\s\/(.+)\//o) do |s|
    @dict[s[0]] = s[1]
    @scan_zip << s
  end
  @dict
end

def postcode2adress(postcode)
  adres = @dict[postcode]
  adres = "not found [input #{postcode}]"  unless adres
  adres
end

postcode_dict(File.join(File.dirname(__FILE__), "SKK-JISYO.zipcode"))

Process.daemon unless $DEBUG
@server = TCPServer.new("localhost", 12345)
@proc = lambda do |s|
  while s.gets
    s.puts("#{postcode2adress($_.chomp)}")
    s.puts("#{cow_dump($$, 'prefork process')}") if $DEBUG
    s.puts("gc count : #{GC.count}") if $DEBUG
    s.close_write
  end
  s.close
end
5.times{ fork{ loop{ @proc.call(@server.accept) } } }
Process.waitall
