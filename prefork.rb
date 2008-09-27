# $Id: prefork.rb,v 1.4 2005/01/17 08:38:56 tommy Exp $
#
# Copyright (C) 2003-2004 TOMITA Masahiro
# tommy@tmtm.org
#

require "socket"
require "tempfile"

class PreFork

  class Children < Array
    def fds()
      self.map{|c| c.active? ? c.from : nil}.compact.flatten
    end

    def pids()
      self.map{|c| c.pid}
    end

    def active()
      self.map{|c| c.active? ? c : nil}.compact
    end

    def idle()
      self.map{|c| c.idle? ? c :  nil}.compact
    end

    def by_fd(fd)
      self.each do |c|
        return c if c.from == fd
      end
      nil
    end

    def cleanup()
      new = Children.new
      self.each do |c|
        begin
          if Process.waitpid(c.pid, Process::WNOHANG) then
            PreFork.log "p: catch exited child #{c.pid}"
            c.exit
          else
            new << c
          end
        rescue Errno::ECHILD
        end
      end
      self.replace new
    end
  end

  class Child
    def initialize(pid, from, to)
      @pid, @from, @to = pid, from, to
      @status = :idle
    end
    # status is one of :idle, :connect, :close, :exit

    attr_accessor :pid, :from, :to

    def event(s)
      if s == nil then
        PreFork.log "p: child #{pid} terminated"
        self.exit
      else
        case s.chomp
        when "connect" then @status = :connect
        when "disconnect" then @status = :idle
        else
          $stderr.puts "unknown status: #{s}"
        end
      end
    end

    def close()
      @to.close unless @to.closed?
      @status = :close
    end

    def exit()
      @from.close unless @from.closed?
      @to.close unless @to.closed?
      @status = :exit
    end

    def idle?()
      @status == :idle
    end

    def active?()
      @status == :idle or @status == :connect
    end
  end

  @@children = Children.new
  @@logging = false

  def self.logging=(f)
    @@logging = f
  end

  def self.log(msg)
    return unless @@logging
    require "syslog"
    if @@logging == :syslog and Syslog.opened? then
      Syslog.info("prefork: %s", msg)
    else
      $stderr.puts "#{Time.now.strftime("%Y-%m-%d %H:%M:%S")} #{File.basename $0}/prefork[#{$$}] #{msg}\n"
      $stderr.flush
    end
  end

  def initialize(*args)
    @handle_signal = false
    @min_servers = 5
    @max_servers = 50
    @max_request_per_child = 50
    @max_idle = 100
    if args[0].is_a? BasicSocket then
      args.each do |s|
	raise "Socket required" unless s.is_a? BasicSocket
      end
      @socks = args
    else
      @socks = [TCPServer.new(*args)]
    end
    @lockfd = Tempfile.new(".prefork")
    @lockf = @lockfd.path
    @lockfd.close
  end

  def sock()
    @socks[0]
  end

  def on_child_start(&block)
    if block == nil then
      raise "block required"
    end
    @on_child_start = block
  end

  def on_child_exit(&block)
    if block == nil then
      raise "block required"
    end
    @on_child_exit = block
  end

  attr_reader :socks
  attr_accessor :min_servers, :max_servers, :max_request_per_child, :max_idle
  alias max_use max_request_per_child
  alias max_use= max_request_per_child=
  attr_writer :on_child_start, :on_child_exit
  attr_accessor :handle_signal

  def start(&block)
    if block == nil then
      raise "block required"
    end
    (@min_servers-@@children.size).times do
      make_child block
    end
    @flag = :in_loop
    while @flag == :in_loop do
      log = false
      r, = IO.select(@@children.fds, nil, nil, 1)
      if r then
        log = true
        r.each do |f|
          c = @@children.by_fd f
          c.event f.gets
        end
      end
      as = @@children.active.size
      @@children.cleanup if @@children.size > as
      break if @flag != :in_loop
      n = 0
      if as < @min_servers then
        n = @min_servers - as
      else
        if @@children.idle.size <= 2 then
          n = 2
        end
      end
      if as + n > @max_servers then
        n = @max_servers - as
      end
      PreFork.log "p: max:#{@max_servers}, min:#{@min_servers}, cur:#{as}, idle:#{@@children.idle.size}: new:#{n}" if n > 0 or log
      n.times do
	make_child block
      end
    end
    @flag = :out_of_loop
    terminate
  end

  def close()
    if @flag != :out_of_loop then
      raise "close() must be called out of start() loop"
    end
    @socks.each do |s|
      s.close
    end
  end

  def stop()
    @flag = :exit_loop
  end

  def terminate()
    @@children.each do |c|
      c.close
    end
  end

  def interrupt()
    Process.kill "TERM", *(@@children.pids) rescue nil
  end

  private

  def exit_child()
    PreFork.log "c: exit"
    @on_child_exit.call if defined? @on_child_exit
    exit!
  end

  def make_child(block)
    PreFork.log "p: make child"
    to_child = IO.pipe
    to_parent = IO.pipe
    pid = fork do
      @@children.map do |c|
        c.from.close unless c.from.closed?
        c.to.close unless c.to.closed?
      end
      @from_parent = to_child[0]
      @to_parent = to_parent[1]
      to_child[1].close
      to_parent[0].close
      child block
    end
    PreFork.log "p: child pid #{pid}"
    @@children << Child.new(pid, to_parent[0], to_child[1])
    to_child[0].close
    to_parent[1].close
  end

  def child(block)
    PreFork.log "c: start"
    trap "TERM" do exit_child end
    @on_child_start.call if defined? @on_child_start
    cnt = 0
    lock = File.open(@lockf, "w")
    last_connect = nil
    while @max_request_per_child == 0 or cnt < @max_request_per_child
      tout = last_connect ? last_connect+@max_idle-Time.now : nil
      break if tout and tout <= 0
      r, = IO.select([@socks, @from_parent].flatten, nil, nil, tout)
      break unless r
      break if r.include? @from_parent
      next unless lock.flock(File::LOCK_EX|File::LOCK_NB)
      r, = IO.select(@socks, nil, nil, 0)
      if r == nil then
        lock.flock(File::LOCK_UN)
        next
      end
      begin
        s = r[0].accept
      rescue Errno::ECONNABORTED, Errno::ECONNREFUSED, Errno::ECONNRESET
        next
      end
      lock.flock(File::LOCK_UN)
      PreFork.log "c: connect from client"
      @to_parent.syswrite "connect\n"
      block.call(s)
      s.close unless s.closed?
      PreFork.log "c: disconnect from client"
      @to_parent.syswrite "disconnect\n" rescue nil
      cnt += 1
      last_connect = Time.now
    end
    exit_child
  end
end
