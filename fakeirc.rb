#!/usr/bin/env ruby
require 'socket'

class IRCSocket < TCPSocket
  def get_message
    line = gets("\r\n", 512)
    raise "Line too long" unless line.end_with? "\r\n"
    STDOUT.puts line
    line =~ /\A(\:([^ ]+) )?([A-Z]+|[0-9]{3})( (.+))?\r\n\z/
    prefix, command, rest = $2, $3, $5
    part1, _, part2 = rest.partition ':'
    args = part1.split ' '
    args << part2 if part2 and part2 != ''
    return prefix, command, args
  end

  def send_message(prefix, command, args)
    if args[-1].include? ' '
      args[-1] = ":#{args[-1]}"
    end
    line = ":#{prefix} #{command.upcase} #{args.join ' '}"
    STDOUT.puts line
    write line+"\r\n"
  end
end

class IRCUser
  def self.get(nick)
    return @@dict[nick]
  end

  def self.rename(oldnick, newnick)
    user = @@dict[oldnick]
    user.nick = newnick
    @@dict.delete(oldnick)
    @@dict[newnick] = user
  end

  attr_reader :nick, :username, :host, :channels

  def initialize(nick, hopcount, username, host, servertoken, umode, realname)
    @nick = nick
    @username = username
    @host = host
    @channels = []

    @@dict ||= {}
    @@dict[@nick] = self
  end

  def join(channel, mode=nil)
    chan = IRCChannel.get(channel) || IRCChannel.new(channel, "")
    chan.users << self
    chan.umodes[@nick] = mode if mode
    self.channels << chan
  end

  def part(channel)
    chan = IRCChannel.get(channel)
    chan.users.delete(self)
    chan.umodes.delete(@nick)
    self.channels.delete(chan)
  end

  def nick=(newnick)
    channels.each do |chan|
      chan.umodes[newnick] = chan.umodes.delete(@nick)
    end
    @nick = newnick
  end
end

class FakeUser < IRCUser
  def initialize(nick, provider="global")
    params = [nick, "0", "~#{nick}", "#{provider}.bridge", "1", "+", nick]
    super.initialize(*params)
    $server.socket.send_message($server.name, "NICK", params)
  end
end

class IRCChannel
  def self.get(name)
    @@dict ||= {}
    return @@dict[name]
  end

  attr_reader :name, :mode, :topic, :users, :umodes
  def initialize(name, mode, topic=nil)
    @name = name
    @mode = mode
    @topic = topic
    @users = []
    @umodes = {}

    @@dict ||= {}
    @@dict[@name] = self
  end
end

class IRCServer
  attr_reader :name
  attr_accessor :socket
  def initialize(name, host, port, password)
    @name = name
    @socket = IRCSocket.new(host, port)
    @socket.write "PASS #{password} 0210-IRC+ fakeirc|0.1:CSX\r\n"
    @socket.write "SERVER #{name} 1 1\r\n"
  end

  def main_loop
    stdin_thr = Thread.new do
      while true
        @socket.write STDIN.gets.strip+"\r\n"
      end
    end

    unix_thr = Thread.new do
      serv = UNIXServer.new("fakeirc.sock")
      while s = serv.accept
        m = s.gets.strip.split
        puts m
        case m[0]
        when "add"
          FakeUser.new m[1]
        when "remove"
        when "join"
        when "part"
        when "message"
        when "action"
        when "listen"
        end
        puts m
        s.close_read
        s.close_write
      end
    end

    while true
      prefix, command, args = @socket.get_message
      case command
      when "PING"
        @socket.write ":#{@name} PONG :#{args[0]}\r\n"
      when "NICK"
        if args.length == 1
          IRCUser.rename(prefix, args[0])
          puts IRCUser.get(args[0]).inspect
        else
          IRCUser.new(*args)
          puts IRCUser.get(args[0]).inspect
        end
      when "CHANINFO"
        IRCChannel.new(*args)
      when "NJOIN"
        nicks = args[1].split(',')
        nicks.each do |nick|
          nick =~ /\A([@%+~]*)(.+)\z/
          IRCUser.get($2).join(args[0], $1)
        end
      when "JOIN"
        chan, _, umode = args[0].partition("\007")
        IRCUser.get(prefix).join(chan, umode)
      when "PART"
        IRCUser.get(prefix).part(args[0])
      else
        #puts [prefix, command, args].inspect
      end
    end
  end
end

$server = IRCServer.new(ARGV[0], ARGV[1], ARGV[2].to_i, ARGV[3])
$server.main_loop
