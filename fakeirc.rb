#!/usr/bin/env ruby
require 'eventmachine'

class IRCUser
  def self.get(nick)
    return @@dict[nick]
  end

  def self.remove(nick, quit_msg=nil)
    @@dict[nick].quit(quit_msg)
    @@dict.delete(nick)
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

  def quit(quit_msg)
    channels.each do |chan|
      chan.users.delete(self)
      chan.umodes.delete(@nick)
    end
  end

  def inspect
    "<IRCUser @nick=#{@nick} @channels=#{@channels.map(&:name).inspect}>"
  end
end

class IRCService < IRCUser
  def initialize(ident, servertoken, distribution, umode, hopcount, info)
    nick, _, ident = ident.partition('!')
    user, _, host = ident.partition('@')
    super(nick, hopcount, user, host, servertoken, umode, info)
  end
end

class FakeUser < IRCUser
  attr_reader :provider

  def initialize(nick, provider=nil)
    provider = "global" if !provider or provider == ""
    @provider = provider
    params = [nick, "0", "~#{provider}", "#{provider}.bridge", "1", "+", nick]
    super(*params)
    $server.send_message($server.name, "NICK", *params)
  end

  def join(channel, mode=nil)
    $server.send_message(@nick, "JOIN", channel)
    super(channel, mode)
  end

  def part(channel)
    $server.send_message(@nick, "PART", channel)
    super(channel)
  end

  def quit(quit_msg)
    $server.send_message(@nick, "QUIT", quit_msg)
    super(quit_msg)
  end
end

class IRCChannel
  def self.get(name)
    @@dict ||= {}
    return @@dict[name]
  end

  attr_reader :name, :mode, :topic, :users, :umodes, :listeners
  def initialize(name, mode, topic=nil)
    @name = name
    @mode = mode
    @topic = topic
    @users = []
    @umodes = {}
    @listeners = []

    @@dict ||= {}
    @@dict[@name] = self
  end

  def privmsg(nick, message)
    @listeners.each do |l|
      if l.provider
        u = IRCUser.get(nick)
        next if u.is_a? FakeUser and u.provider == l.provider
      end
      if message =~ /\A\001ACTION (.+)\001\z/
        l.send_data "* #{nick} #{$1}\n"
      else
        l.send_data "<#{nick}> #{message}\n"
      end
    end
  end

  def inspect
    "<IRCChannel @name=#{@name} @users=#{@users.map(&:nick).inspect}>"
  end
end

class IRCServer < EventMachine::Connection
  include EventMachine::Protocols::LineProtocol
  attr_reader :name
  def initialize(name, host, port, password)
    super
    @name = name
    @password = password
  end

  def post_init
    send_message nil, "PASS", @password, "0210-IRC+", "fakeirc|0.1:CSX"
    send_message nil, "SERVER", @name, "1", "1"
  end

  def receive_line(line)
    STDOUT.puts line
    line =~ /\A(\:([^ ]+) )?([A-Z]+|[0-9]{3})( (.+))?\r?\z/ or raise "Bad format"
    prefix, command, rest = $2, $3, $5
    part1, _, part2 = rest.partition ':'
    args = part1.split ' '
    args << part2 if part2 and part2 != ''
    receive_message prefix, command, args
  end

  def receive_message(prefix, command, args)
    case command
    when "PING"
      send_message prefix||@name, "PONG", *args
    when "NICK"
      if args.length == 1
        IRCUser.rename(prefix, args[0])
      else
        IRCUser.new(*args)
      end
    when "SERVICE"
      IRCService.new(*args)
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
    when "PRIVMSG"
      chan = IRCChannel.get(args[0])
      if chan
        chan.privmsg(prefix, args[1])
      end
    else
      #puts [prefix, command, args].inspect
    end
  end

  def send_message(prefix, command, *args)
    args.compact!
    if args.length > 0
      args[-1] = ":#{args[-1]}"
    end
    line = ""
    line += ":#{prefix} " if prefix
    line += command.upcase
    line += " #{args.join ' '}" if args.length > 0
    STDOUT.puts line
    send_data line+"\r\n"
  end
end

module UnixServer
  include EM::Protocols::LineProtocol
  attr_reader :provider

  def receive_line line
    args = line.split ' '
    case args[0]
    when "add"
      FakeUser.new(args[1], args[2]) unless IRCUser.get(args[1])
      send_data "\n"
    when "remove"
      IRCUser.remove(args[1], args[2..args.length].join(' ')) if IRCUser.get(args[1])
      send_data "\n"
    when "join"
      IRCUser.get(args[1]).join(args[2])
      send_data "\n"
    when "part"
      IRCUser.get(args[1]).part(args[2])
      send_data "\n"
    when "message"
      msg = args[3..args.length].join(' ')
      $server.send_message args[1], "PRIVMSG", args[2], msg
      send_data "\n"
      IRCChannel.get(args[2]).privmsg(args[1], msg)
    when "away"
      $server.send_message $server.name, "MODE", args[1], "+a"
      send_data "\n"
    when "unaway"
      $server.send_message $server.name, "MODE", args[1], "-a"
      send_data "\n"
    when "action"
      msg = "\001ACTION #{args[3..args.length].join(' ')}\001"
      $server.send_message args[1], "PRIVMSG", args[2], msg
      send_data "\n"
      IRCChannel.get(args[2]).privmsg(args[1], msg)
    when "listen"
      @provider = args[2] if args[2]
      chan = IRCChannel.get(args[1]) || IRCChannel.new(args[1], "")
      chan.listeners << self
    end
  end
end

class KeyboardHandler < EM::Connection
  include EM::Protocols::LineProtocol
  def receive_line line
    $server.send_data line.strip+"\r\n"
  end
end

class UnixClient < EM::Connection
  include EM::Protocols::LineProtocol
  def initialize(persistent, *args)
    @persistent = persistent
    @args = args
    super
  end

  def post_init
    send_data(@args.join(' ')+"\n")
  end

  def receive_line line
    puts line
    STDOUT.flush
    close_connection_after_writing unless @persistent
  end

  def unbind
    EM.stop_event_loop
  end
end

def usage
  puts <<-eos
fakeirc <name> <host> <port> <password>
fakeirc add <user> [<provider>]
fakeirc remove <user> [<quitmessage>]
fakeirc join <user> <channel>
fakeirc part <user> <channel>
fakeirc away <user>
fakeirc unaway <user>
fakeirc message <user> <channel> <message>
fakeirc action <user> <channel> <action>
fakeirc listen <channel>
eos
end

if ARGV.length == 0
  usage
  exit
end

case ARGV[0]
when "add", "remove", "join", "part", "away", "unaway", "message", "action"
  EventMachine.run do
    EventMachine.connect '/tmp/fakeirc/fakeirc.sock', port=nil, handler=UnixClient, false, *ARGV
  end
when "listen"
  begin
    EventMachine.run do
      EventMachine.connect '/tmp/fakeirc/fakeirc.sock', port=nil, handler=UnixClient, true, *ARGV
    end
  rescue Interrupt
  end
when "help"
  usage
  exit
else
  if ARGV.length != 4
    usage
    exit
  end
  begin
    EventMachine.run do
      $server = EventMachine.connect(ARGV[1], ARGV[2].to_i, IRCServer, ARGV[0], ARGV[1], ARGV[2].to_i, ARGV[3])
      Dir.mkdir("/tmp/fakeirc") unless File.exist? "/tmp/fakeirc"
      EventMachine.start_server("/tmp/fakeirc/fakeirc.sock", handler=UnixServer)
      EventMachine.open_keyboard KeyboardHandler
    end
  rescue Interrupt
    `rm /tmp/fakeirc/fakeirc.sock`
  end
end
