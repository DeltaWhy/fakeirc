#!/usr/bin/ruby
require 'open3'
require 'shellwords'
require 'json'

FAKEIRC=File.join File.dirname(__FILE__), '..', 'fakeirc.rb'
def fakeirc(*args)
  %x( #{FAKEIRC} #{args.map(&:shellescape).join(' ')} )
end

if ARGV.length != 4
  puts "#{File.basename(__FILE__)} <container-name> <provider> <channel> <suffix>"
  exit
end
CONTAINER = ARGV[0]
PROVIDER = ARGV[1]
CHANNEL = ARGV[2]
SUFFIX = "[#{ARGV[3]}]"

stdin, stdout, stderr, wait_thr = Open3.popen3("docker attach --sig-proxy=false #{CONTAINER}")

thr = Thread.new do
  loop do
    m = stdout.gets
    STDERR.puts m
    STDERR.flush
    if m.strip =~ /\A\[[0-9:]+\] \[[^\]]+\]: \<(.+)\> (.+)\z/
      fakeirc 'message', $1+SUFFIX, "#{CHANNEL}", $2
    elsif m.strip =~ /\A\[[0-9:]+\] \[[^\]]+\]: \* ([^ ]+) (.+)\z/
      fakeirc 'action', $1+SUFFIX, "#{CHANNEL}", $2
    elsif m.strip =~ /\A\[[0-9:]+\] \[[^\]]+\]: ([^ ]+) joined the game\z/
      fakeirc 'add', $1+SUFFIX, "#{PROVIDER}"
      fakeirc 'join', $1+SUFFIX, "#{CHANNEL}"
    elsif m.strip =~ /\A\[[0-9:]+\] \[[^\]]+\]: ([^ ]+) left the game\z/
      fakeirc 'remove', $1+SUFFIX
    end
  end
end

stdin2, stdout2, stderr2, wait_thr2 = Open3.popen3("#{FAKEIRC} listen #{CHANNEL.shellescape} #{PROVIDER}")

thr2 = Thread.new do
  loop do
    m = stdout2.gets.strip
    STDERR.puts m
    STDERR.flush
    if m =~ /\A\<([^>]+)\> (.+)\z/
      cmd = "tellraw @a [\"\",{\"text\":\"[\"},{\"text\":\"#{$1}\",\"color\":\"gray\"},{\"text\":\"] \",\"color\":\"none\"},{\"text\":#{JSON.dump $2},\"color\":\"none\"}]"
      stdin.puts cmd
      stdin.flush
    elsif m =~ /\A* ([^ ]+) (.+)\z/
      cmd = "tellraw @a [\"\",{\"text\":\"* \"},{\"text\":\"#{$1}\",\"color\":\"gray\"},{\"text\":\" \",\"color\":\"none\"},{\"text\":#{JSON.dump $2},\"color\":\"none\"}]"
      stdin.puts cmd
      stdin.flush
    end
  end
end

begin
  thr2.join
  thr.join
rescue Interrupt
end