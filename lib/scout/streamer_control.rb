module Scout
  class StreamerControl < DaemonSpawn::Base

    # args are: server, key, history, plugin_ids, log
    def start(args)
      puts "StreamerControl#start PID=#{pid}"
      server,key,history,plugin_ids,log = args
      $continue_streaming = true #

      @scout = Scout::Streamer.new(server, key, history, plugin_ids, log)
      puts "StreamerControl - done. Removing pid_file at #{pid_file} containing PID=#{pid}"
      File.unlink(pid_file) if File.exists?(pid_file) # a better way of doing this?
    end

    def stop
      $continue_streaming = false
    end
  end
end


# This is how to start using this file as a start/stop command processor, and passing arguments in via command line:
# Since there's no second argument to StreamerControl.spawn!, it uses command-line arguments.
#Scout::StreamerControl.spawn!({:log_file => File.expand_path('~/.scout/scout_streamer.log'),
#                :pid_file => File.expand_path('~/.scout/scout_streamer.pid'),
#                :sync_log => true,
#                :working_dir => File.dirname(__FILE__)})


# This is how you start it from anywhere in code:
# Since there's a second argument to StreamerControl.spawn!, it uses those instead of command-line arguments.
#Scout::StreamerControl.start({:log_file => File.expand_path('~/.scout/scout_streamer.log'),
#                :pid_file => File.expand_path('~/.scout/scout_streamer.pid'),
#                :sync_log => true,
#                :working_dir => File.dirname(__FILE__)},
#                ["ServerInstance", "abcd-1234-123g2-12321", "~/.scout/history.yml",[1,2,3,4],nil])

# This is how you stop in anywhere in code:
# Since there's a second argument to StreamerControl.spawn!, it uses those instead of command-line arguments.
#Scout::StreamerControl.stop({:log_file => File.expand_path('~/.scout/scout_streamer.log'),
#                :pid_file => File.expand_path('~/.scout/scout_streamer.pid'),
#                :sync_log => true,
#                :working_dir => File.dirname(__FILE__)},[])
