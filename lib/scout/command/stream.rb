#!/usr/bin/env ruby -wKU

module Scout
  class Command
    class Stream < Command
      PID_FILENAME="streamer.pid"

      def run
        @pid_file = File.join(config_dir, PID_FILENAME)
        @key = @args[0]
        daemon_command = @args[1]

        log.info("in Scout::Command::Stream. @args=#{@args.inspect}")

        if !@key
          puts "usage: scout stream [your_scout_key] [start|stop|status]"
          exit(1)
        end

        if !daemon_command
          run_directly
          exit(0)
        end

        if daemon_command == "start"
          log.info "daemon_command=start"
          if File.exist?(@pid_file)
            puts "Can't start streamer -- PID already exists at #{@pid_file} -- #{File.read(@pid_file)}"
          else
            puts "Forking ... "
            cmd="#{program_path} stream #{@key} -s#{server} -d#{history}"
            log.info "about to run cmd: #{cmd}"
            streamer = fork do
              exec cmd
            end
            Process.detach(streamer)
            puts "forked and detached PID: #{streamer}"
          end
        elsif daemon_command == "stop"
          if File.exist?(@pid_file)
            pid=File.read(@pid_file).chomp.to_i
            log.info "Terminating: #{pid}"
            res=Process.kill("INT",pid)
            ps = `ps -ef | grep #{pid}`
            log.info ".. done: #{res}. ps=#{ps}"
          else
            puts "Can't stop streamer -- NO PID exists at #{@pid_file}"
          end
        elsif daemon_command == "status"
          if File.exist?(@pid_file)
            file=File.new(@pid_file)
            pid=file.read
            puts "streamer running since #{file.ctime} with pid #{pid}"
          else
            puts "streamer not running"
          end
        else
          puts "usage: scout stream [your_scout_key] [start|stop|status]"
          exit(1)
        end
      end

      private

      def run_directly
        File.open(@pid_file, File::CREAT|File::EXCL|File::WRONLY) do |pid|
          pid.puts $$
        end
        at_exit do
          begin
            File.unlink(@pid_file)
          rescue
            log.error "Unable to unlink pid file:  #{$!.message}" if log
          end
        end

        @scout = Scout::Streamer.new(server, @key, history, log)
      end

      def growl(message)`growlnotify -m '#{message.gsub("'","\'")}'`;end

    end
  end
end
