#!/usr/bin/env ruby -wKU

require "logger"

module Scout
  class Command
    class Stream < Command
      PID_FILENAME="streamer.pid"

      def run
        @key = @args[0]
        daemon_command = @args[1]
        @plugin_ids = @options[:plugin_ids]

        if !@key
          puts "usage: scout stream [your_scout_key] [start|stop]"
          exit(1)
        end

        # server and history methods are inherited from Scout::Command base class
        streamer_log_file=File.join(File.dirname(history),"scout_streamer.log")
        streamer_pid_file=File.join(File.dirname(history),"scout_streamer.pid")

        streamer_control_options = {:log_file => streamer_log_file,
                                    :pid_file => streamer_pid_file,
                                    :sync_log => true,
                                    :working_dir => File.dirname(history)}

        # we use STDOUT for the logger because daemon_spawn directs STDOUT to a log file
        streamer_control_args = [server, @key, history, @plugin_ids, Logger.new(STDOUT)]

        if daemon_command.include? "start" # can be 'start' or 'restart'
          if File.exists?(streamer_pid_file)
            puts "PID file existed. Restarting ..."
            Scout::StreamerControl.restart(streamer_control_options,streamer_control_args)
          else
            puts "Starting ... "
            Scout::StreamerControl.start(streamer_control_options,streamer_control_args)
          end
        elsif daemon_command == "stop"
          puts "Stopping ..."
          Scout::StreamerControl.stop(streamer_control_options,[])
        else
          puts "usage: scout stream [your_scout_key] [start|stop]"
          exit(1)
        end
      end
    end
  end
end
