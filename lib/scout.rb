#!/usr/bin/env ruby -wKU

module Scout
  VERSION = "5.4.0".freeze
end

require "scout/command"
require "scout/plugin"
require "scout/plugin_options"
require "scout/scout_logger"
require "scout/server_base"
require "scout/server"
require "scout/streamer"
