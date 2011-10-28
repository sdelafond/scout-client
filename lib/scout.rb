#!/usr/bin/env ruby -wKU

module Scout
  VERSION = "5.4.0".freeze
end

require "scout/command"
require "scout/plugin"
require "scout/plugin_options"
require "scout/scout_logger"
require "scout/server"

# temporary hack so we don't fail normal Scout operations on servers that don't have em-websocket gem installed
begin
  require "scout/streamer"
rescue Exception=>e
  puts e.message if $stdin.tty?
end
