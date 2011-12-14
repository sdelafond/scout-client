require 'rubygems'
require 'json'

module Scout
  class Streamer < Scout::ServerBase
    MAX_DURATION = 60*30 # will shut down automatically after this many seconds
    SLEEP = 1

    # * history_file is the *path* to the history file
    # * plugin_ids is an array of integers
    def initialize(server, client_key, history_file, plugin_ids, streaming_key, logger = nil)
      @server       = server
      @client_key   = client_key
      @history_file = history_file
      @history      = Hash.new
      @logger       = logger

      @plugin_hashes = []

      Pusher.app_id = '11495'
      Pusher.key = 'a95aa7293cd158100246'
      Pusher.secret = '9c13ccfe325fe3ae682d'

      streamer_start_time = Time.now

      info("Streamer PID=#{$$} starting")

      hostname=Socket.gethostname
      # load history
      load_history

      # get the array of plugins, AKA the plugin plan
      @plugin_plan = Array(@history["old_plugins"])
      info("Starting streamer with key=#{streaming_key} and plugin_ids: #{plugin_ids.inspect}. #{@history_file} includes plugin ids #{@plugin_plan.map{|p|p['id']}.inspect}")

      # Compile instances of the plugins specified in the passed plugin_ids
      plugin_ids.each_with_index do |plugin_id,i|
        plugin_data=@plugin_plan.find{|plugin| plugin['id'] && plugin['id'].to_i == plugin_id}
        if plugin_data
          begin
            plugin=get_instance_of(plugin_data, plugin_id)
            info("#{i+1}) plugin_id=#{plugin_id} - instance of #{plugin.class.name} created for #{plugin_data['name']}" )
            if plugin.is_a?(Plugin) # safety check that it's an instance of Plugin
              @plugin_hashes.push(:instance=>plugin, :id=>plugin_id, :name=>plugin_data['name'])
            end
          rescue Exception
            error("Encountered an error compiling: #{$!.message}")
            error $!.backtrace.join('\n')
          end
        else
          info("#{i+1}) plugin_id=#{plugin_id} specified in #{plugin_ids.inspect} but not found in #{@history_file}")
        end
      end

      info "Finished compilation. #{@plugin_plan.size} plugins; #{@plugin_hashes.size} instances instantiated"

      # main loop. Continue running until global $continue_streaming is set to false OR we've been running for MAX DURATION
      iteration=1 # use this to log the data at a couple points
      while(streamer_start_time+MAX_DURATION > Time.now && $continue_streaming) do
        plugins=[]
        @plugin_hashes.each_with_index do |plugin_hash,i|
          plugin=plugin_hash[:instance]
          start_time=Time.now
          plugin.reset!
          plugin.run
          duration=((Time.now-start_time)*1000).to_i

          plugins << {:duration=>duration,
                     :fields=>plugin.reports.inject{|memo,hash|memo.merge(hash)},
                     :name=>plugin_hash[:name],
                     :id=>plugin_hash[:id]}
        end

        bundle={:hostname=>hostname,
                 :server_time=>Time.now.strftime("%I:%M:%S %p"),
                 :num_processes=>`ps -e | wc -l`.chomp.to_i,
                 :plugins=>plugins }

        begin
          Pusher[streaming_key].trigger!('server_data', bundle)
        rescue Pusher::Error => e
          # (Pusher::AuthenticationError, Pusher::HTTPError, or Pusher::Error)
          error "Error pushing data: #{e.message}"
        end

        if iteration == 2 || iteration == 100
          info "Run #{iteration} data dump:"
          info bundle.to_json
        end

        if false
          # debugging
          File.open(File.join(File.dirname(@history_file),"debug.txt"),"w") do |f|
            f.puts "... sleeping @ #{Time.now.strftime("%I:%M:%S %p")}..."
            f.puts bundle.to_yaml
          end
        end

        sleep(SLEEP)
        iteration+=1
      end

      info("Streamer PID=#{$$} ending.")
    end

    
    private

    # plugin is a hash of plugin data from the history file (id, name, code, etc).
    # This plugin returns an instantiated instance of the plugin
    def get_instance_of(plugin, plugin_id)

      # take care of plugin overrides
      local_path = File.join(File.dirname(@history_file), "#{plugin_id}.rb")
      if File.exist?(local_path)
        code_to_run = File.read(local_path)
      else
        code_to_run=plugin['code'] || ""
      end

      id_and_name = "#{plugin_id}-#{plugin['name']}".sub(/\A-/, "")
      last_run    = @history["last_runs"][id_and_name] ||
                    @history["last_runs"][plugin['name']]
      memory      = @history["memory"][id_and_name] ||
                    @history["memory"][plugin['name']]
      options=(plugin['options'] || Hash.new)
      options.merge!(:tuner_days=>"")

      code_class=Plugin.extract_code_class(code_to_run)

      # eval the plugin code if it's not already defined
      if !Plugin.const_defined?(code_class)
        eval(code_to_run, TOPLEVEL_BINDING, plugin['path'] || plugin['name'] )
      end

      # now that we know the class is defined, reference its class
      klass=Scout::Plugin.const_get(code_class)

      # turn certain methods into null-ops, so summaries aren't generated. Note that this is ad-hoc, and not future-proof.
      if klass.name=="RailsRequests"; def klass.analyze;end;end
      if klass.name=="ApacheAnalyzer"; def klass.generate_log_analysis;end;end

      # finally, return an instance of the plugin
      klass.load(last_run, (memory || Hash.new), options)
    end


    def load_history
      begin
        debug "Loading history file..."
        contents=File.read(@history_file)
        @history = YAML.load(contents)
      rescue => e
        info "Couldn't load or parse the history file at #{@history_file}. Exiting."
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