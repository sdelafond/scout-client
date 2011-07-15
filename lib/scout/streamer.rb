require 'rubygems'
require 'em-websocket'
require 'json'

module Scout
  class Streamer
    def initialize(history_file, logger = nil)
      @history_file = history_file
      @history      = Hash.new
      @logger       = logger

      @plugins = []

      hostname=`hostname`.chomp
      $num_connections=0
      $bundle={}

      # load history
      load_history

      # get the array of plugins, AKA the plugin plan
      @plugin_plan = Array(@history["old_plugins"])

      #puts "history contains keys: #{@history.keys.join(', ')}"
      #puts "Options: #{@plugin_plan.first["options"].inspect}"
      #puts "Code is #{@plugin_plan.first["code"].size} bytes"

      # iterate through the plan and compile each plugin. We only compile plugins once at the beginning of the run
      @plugin_plan.each do |plugin|
        begin
          compile_plugin(plugin)
        rescue Exception
          error("Encountered an error: #{$!.message}")
          puts $!.backtrace.join('\n')
        end
      end

      # main loop. Generate stats only if one or more clients are connected via websockets
      Thread.new do
        while(true) do
          # only run plugins if there are some connections
          if $num_connections > 0
            plugins=[]
            puts "running!"
            @plugins.each_with_index do |plugin,i|
              start_time=Time.now
              plugin.reset!
              plugin.run
              duration=((Time.now-start_time)*1000).to_i

              plugins << {:duration=>duration,
                         :fields=>plugin.reports.inject{|memo,hash|memo.merge(hash)},
                         :name=>@plugin_plan[i]["name"]}
            end

            $bundle={:hostname=>hostname,
                     :num_connections=>$num_connections,
                     :server_time=>Time.now.strftime("%I:%M:%S %p"),
                     :num_processes=>`ps -e | wc -l`,
                     :plugins=>plugins }

          end

          puts "... sleeping @ #{Time.now.strftime("%I:%M:%S %p")}..."
          sleep(2)
        end
      end

      # Start the EventMachine loop, waiting for websocket connections.
      EventMachine.run do
        EventMachine::WebSocket.start(:host => "0.0.0.0", :port => 5959) do |ws|
          ws.onopen    {
            $num_connections +=1
            puts "switching ON" if $num_connections > 0
          }
          ws.onmessage { |msg| ws.send($bundle.to_json) }
          ws.onclose   {
            $num_connections = $num_connections -1
            puts "switching OFF" if $num_connections == 0
          }
        end
      end
    end

    
    private

    # sets up the @plugins array
    def compile_plugin(plugin)
      code_to_run=plugin['code']
      if ["class MPstat","class ApacheLoad"].any?{|snippit| code_to_run.include?(snippit) }
        code_to_run="class DummyPlugin < Scout::Plugin;def build_report;end;end"
        plugin['name']=plugin['name']+" (disabled)"
      end
      id_and_name = "#{plugin['id']}-#{plugin['name']}".sub(/\A-/, "")
      plugin_id = plugin['id']
      last_run    = @history["last_runs"][id_and_name] ||
                    @history["last_runs"][plugin['name']]
      memory      = @history["memory"][id_and_name] ||
                    @history["memory"][plugin['name']]
      options=(plugin['options'] || Hash.new)
      options.merge!(:tuner_days=>"")
      begin
        eval( code_to_run,
              TOPLEVEL_BINDING,
              plugin['path'] || plugin['name'] )
        info "Plugin compiled. It's a #{Plugin.last_defined}"
        @plugins << Plugin.last_defined.load(last_run, (memory || Hash.new), options)
        # turn RailsRequest#analyze method into a null-op -- we don't want summaries being generated
        if @plugins.last.class.name=="RailsRequests"
          p=@plugins.last
          def p.analyze; end
        end
      rescue Exception
        raise if $!.is_a? SystemExit
        error "Plugin would not compile: #{$!.message}"
        return
      end
    end


    def load_history
      if !File.exist?(@history_file) || File.zero?(@history_file)
        create_blank_history
      end
      debug "Loading history file..."
      contents=File.read(@history_file)
      begin
        @history = YAML.load(contents)
      rescue => e
        info "Couldn't parse the history file. Exiting"
        exit(1)
      end
      info "History file loaded."
    end

    # Forward Logger methods to an active instance, when there is one.
    def method_missing(meth, *args, &block)
      if (Logger::SEV_LABEL - %w[ANY]).include? meth.to_s.upcase
        @logger.send(meth, *args, &block) unless @logger.nil?
      else
        super
      end
    end

  end
end