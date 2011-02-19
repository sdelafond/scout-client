#!/usr/bin/env ruby -wKU

require "net/https"
require "uri"
require "yaml"
require "timeout"
require "stringio"
require "zlib"
require "socket"
require "base64"

$LOAD_PATH << File.join(File.dirname(__FILE__), *%w[.. .. vendor json_pure lib])
require "json"

module Scout
  class Server
    # A new class for plugin Timeout errors.
    class PluginTimeoutError < RuntimeError; end
    # A new class for API Timeout errors.
    class APITimeoutError < RuntimeError; end
    
    # Headers passed up with all API requests.
    HTTP_HEADERS = { "Client-Version"  => Scout::VERSION,
                     "Client-Hostname" => Socket.gethostname,
                     "Accept-Encoding" => "gzip" }
    
    # 
    # A plugin cannot take more than DEFAULT_PLUGIN_TIMEOUT seconds to execute, 
    # otherwise, a timeout error is generated.  This can be overriden by
    # individual plugins.
    # 
    DEFAULT_PLUGIN_TIMEOUT = 60
    #
    # A fuzzy range of seconds in which it is okay to rerun a plugin.
    # We consider the interval close enough at this point.
    # 
    RUN_DELTA = 30

    attr_reader :new_plan
    attr_reader :directives

    # Creates a new Scout Server connection.
    def initialize(server, client_key, history_file, logger = nil)
      @server       = server
      @client_key   = client_key
      @history_file = history_file
      @history      = Hash.new
      @logger       = logger
      @plugin_plan  = []
      @directives   = {} # take_snapshots, interval, sleep_interval
      @new_plan     = false
      @local_plugin_path = File.dirname(history_file) # just put overrides and ad-hoc plugins in same directory as history file.

      # the block is only passed for install and test, since we split plan retrieval outside the lockfile for run
      if block_given?
        load_history
        yield self
        save_history
      end
    end

    #
    # Retrieves the Plugin Plan from the server. This is the list of plugins
    # to execute, along with all options.
    #
    # This method has a couple of side effects:
    # 1) it sets the @plugin_plan with either A) whatever is in history, B) the results of the /plan retrieval
    # 2) it sets @checkin_to = true IF so directed by the scout server
    def fetch_plan
      url = urlify(:plan)
      info "Pinging server at #{url}..."
      headers = {"x-scout-tty" => ($stdin.tty? ? 'true' : 'false')}
      if @history["plan_last_modified"] and @history["old_plugins"]
        headers["If-Modified-Since"] = @history["plan_last_modified"]
      end
      get(url, "Could not retrieve plan from server.", headers) do |res|
        if res.is_a? Net::HTTPNotModified
          info "Plan not modified. Will reuse saved plan."
          @plugin_plan = Array(@history["old_plugins"])
          # Add local plugins to the plan. Note that local plugins are NOT saved to history file
          @plugin_plan += get_local_plugins
          @directives = @history["directives"] || Hash.new

        else
          info "plan has been modified. Will run the new plan now."
          begin
            body = res.body
            if res["Content-Encoding"] == "gzip" and body and not body.empty?
              body = Zlib::GzipReader.new(StringIO.new(body)).read
            end

            body_as_hash = JSON.parse(body)

            # Ensure all the plugins in the new plan are properly signed. Load the public key for this.
            public_key_text = File.read(File.join( File.dirname(__FILE__), *%w[.. .. data code_id_rsa.pub] ))
            debug "Loaded public key used for verifying code signatures (#{public_key_text.size} bytes)"
            code_public_key = OpenSSL::PKey::RSA.new(public_key_text)

            temp_plugins=Array(body_as_hash["plugins"])
            plugin_signature_error = false
            temp_plugins.each do |plugin|
              signature=plugin['signature']
              id_and_name = "#{plugin['id']}-#{plugin['name']}".sub(/\A-/, "")
puts "id_and_name: #{id_and_name}"
              if signature
                code=plugin['code'].gsub(/ +$/,'') # we strip trailing whitespace before calculating signatures. Same here.
                decoded_signature=Base64.decode64(signature)
                if !code_public_key.verify(OpenSSL::Digest::SHA1.new, decoded_signature, code)
                  warn "#{id_and_name} signature doesn't match!"
                  plugin_signature_error=true
                end
              else
                warn "#{id_and_name} has no signature!"
                plugin_signature_error=true
              end
            end


            if(!plugin_signature_error)
              @plugin_plan = temp_plugins
              @directives = body_as_hash["directives"].is_a?(Hash) ? body_as_hash["directives"] : Hash.new
              @history["plan_last_modified"] = res["last-modified"]
              @history["old_plugins"]        = @plugin_plan.clone # important that the plan is cloned -- we're going to add local plugins, and they shouldn't go into history
              @history["directives"]         = @directives

              info "Plan loaded.  (#{@plugin_plan.size} plugins:  " +
                   "#{@plugin_plan.map { |p| p['name'] }.join(', ')})" +
                   ". Directives: #{@directives.to_a.map{|a|  "#{a.first}:#{a.last}"}.join(", ")}"

              @new_plan = true # used in determination if we should checkin this time or not
            else
              info "There was a problem with plugin signatures. Reusing old plan."
              @plugin_plan = Array(@history["old_plugins"])
              @directives = @history["directives"] || Hash.new
            end

            # Add local plugins to the plan. Note that local plugins are NOT saved to history file
            @plugin_plan += get_local_plugins

          rescue Exception =>e
            fatal "Plan from server was malformed: #{e.message} - #{e.backtrace}"
            exit
          end
        end
      end
    end

    # returns an array of hashes representing local plugins found on the filesystem
    # The glob pattern requires that filenames begin with a letter,
    # which excludes plugin overrides (like 12345.rb)
    def get_local_plugins
      local_plugin_paths=Dir.glob(File.join(@local_plugin_path,"[a-zA-Z]*.rb"))
      local_plugin_paths.map do |plugin_path|
        begin
          {
            'name' => File.basename(plugin_path),
            'local_filename' => File.basename(plugin_path),
            'origin' => 'LOCAL',
            'code' => File.read(plugin_path),
            'interval' => 0
          }
        rescue => e
          info "Error trying to read local plugin: #{plugin_path} -- #{e.backtrace.join('\n')}"
          nil
        end
      end.compact
    end

    # To distribute pings across a longer timeframe, the agent will sleep for a given
    # amount of time. When using the --force option the sleep_interval is ignored.
    def sleep_interval
      (@history['directives'] || {})['sleep_interval'].to_f
    end

    # uses values from history and current time to determine if we should checkin at this time
    def time_to_checkin?
      @history['last_checkin'] == nil ||
              @directives['interval'] == nil ||
              (Time.now.to_i - Time.at(@history['last_checkin']).to_i).abs+15 > @directives['interval'].to_i*60
    rescue
      debug "Failed to calculate time_to_checkin. @history['last_checkin']=#{@history['last_checkin']}. "+
              "@directives['interval']=#{@directives['interval']}. Time.now.to_i=#{Time.now.to_i}"
      return true
    end

    # uses values from history and current time to determine if we should ping the server at this time
    def time_to_ping?
      return true if
      @history['last_ping'] == nil ||
              @directives['ping_interval'] == nil ||
              (Time.now.to_i - Time.at(@history['last_ping']).to_i).abs+15 > @directives['ping_interval'].to_i*60
    rescue
      debug "Failed to calculate time_to_ping. @history['last_ping']=#{@history['last_ping']}. "+
              "@directives['ping_interval']=#{@directives['ping_interval']}. Time.now.to_i=#{Time.now.to_i}"
      return true
    end

    # returns a human-readable representation of the next checkin, i.e., 5min 30sec
    def next_checkin
      secs= @directives['interval'].to_i*60 - (Time.now.to_i - Time.at(@history['last_checkin']).to_i).abs
      minutes=(secs.to_f/60).floor
      secs=secs%60
      "#{minutes}min #{secs} sec"
    rescue
      "[next scout invocation]"
    end

    # Runs all plugins from the given plan. Calls process_plugin on each plugin.
    # @plugin_execution_plan is populated by calling fetch_plan
    def run_plugins_by_plan
      prepare_checkin
      @plugin_plan.each do |plugin|
        begin
          process_plugin(plugin)
        rescue Exception
puts "************************************ here"
          @checkin[:errors] << build_report(
            plugin,
            :subject => "Exception:  #{$!.message}.",
            :body    => $!.backtrace
          )
          error("Encountered an error: #{$!.message}")
          puts $!.backtrace.join('\n')
        end
      end
      take_snapshot if @directives['take_snapshots']
      checkin
    end
    
    # 
    # This is the heart of Scout.  
    # 
    # First, it determines if a plugin is past interval and needs to be run.
    # If it is, it simply evals the code, compiling it.
    # It then loads the plugin and runs it with a PLUGIN_TIMEOUT time limit.
    # The plugin generates data, alerts, and errors. In addition, it will
    # set memory and last_run information in the history file.
    #
    # The plugin argument is a hash with keys: id, name, code, timeout, options, signature.
    def process_plugin(plugin)
      info "Processing the '#{plugin['name']}' plugin:"
      id_and_name = "#{plugin['id']}-#{plugin['name']}".sub(/\A-/, "")
      plugin_id = plugin['id']
      last_run    = @history["last_runs"][id_and_name] ||
                    @history["last_runs"][plugin['name']]
      memory      = @history["memory"][id_and_name] ||
                    @history["memory"][plugin['name']]
      run_time    = Time.now
      delta       = last_run.nil? ? nil : run_time -
                                          (last_run + plugin['interval'] * 60)
      if last_run.nil? or delta.between?(-RUN_DELTA, 0) or delta >= 0
        debug "Plugin is past interval and needs to be run.  " +
              "(last run:  #{last_run || 'nil'})"
        code_to_run = plugin['code']
        if plugin_id && plugin_id != ""
          override_path=File.join(@local_plugin_path, "#{plugin_id}.rb")
          # debug "Checking for local plugin override file at #{override_path}"
          if File.exist?(override_path)
            code_to_run = File.read(override_path)
            debug "Override file found - Using #{code_to_run.size} chars of code in #{override_path} for plugin id=#{plugin_id}"
            plugin['origin'] = "OVERRIDE"
          end
        end
        debug "Compiling plugin..."
        begin
          eval( code_to_run,
                TOPLEVEL_BINDING,
                plugin['path'] || plugin['name'] )
          info "Plugin compiled."
        rescue Exception
          raise if $!.is_a? SystemExit
          error "Plugin would not compile: #{$!.message}"
          @checkin[:errors] << build_report(plugin,:subject => "Plugin would not compile", :body=>"#{$!.message}\n\n#{$!.backtrace}")
          return
        end
        debug "Loading plugin..."
        if job = Plugin.last_defined.load( last_run, (memory || Hash.new),
                                           plugin['options'] || Hash.new )
          info "Plugin loaded."
          debug "Running plugin..."
          begin
            data    = {}
            timeout = plugin['timeout'].to_i
            timeout = DEFAULT_PLUGIN_TIMEOUT unless timeout > 0
            Timeout.timeout(timeout, PluginTimeoutError) do
              data = job.run
            end
          rescue Timeout::Error, PluginTimeoutError
            error "Plugin took too long to run."
            @checkin[:errors] << build_report(plugin,
                                              :subject => "Plugin took too long to run",
                                              :body=>"Execution timed out.")
            return
          rescue Exception
            raise if $!.is_a? SystemExit
            error "Plugin failed to run: #{$!.class}: #{$!.message}\n" +
                  "#{$!.backtrace.join("\n")}"
            @checkin[:errors] << build_report(plugin,
                                              :subject => "Plugin failed to run",
                                              :body=>"#{$!.class}: #{$!.message}\n#{$!.backtrace.join("\n")}")
          end
          info "Plugin completed its run."
          
          %w[report alert error summary].each do |type|
            plural  = "#{type}s".sub(/ys\z/, "ies").to_sym
            reports = data[plural].is_a?(Array) ? data[plural] :
                                                  [data[plural]].compact
            if report = data[type.to_sym]
              reports << report
            end
            reports.each do |fields|
              @checkin[plural] << build_report(plugin, fields)
            end
          end
          
          @history["last_runs"].delete(plugin['name'])
          @history["memory"].delete(plugin['name'])
          @history["last_runs"][id_and_name] = run_time
          @history["memory"][id_and_name]    = data[:memory]
        else
          @checkin[:errors] << build_report(
            plugin,
            :subject => "Plugin would not load."
          )
        end
      else
        debug "Plugin does not need to be run at this time.  " +
              "(last run:  #{last_run || 'nil'})"
      end
      data
    ensure
      if Plugin.last_defined
        debug "Removing plugin code..."
        begin
          Object.send(:remove_const, Plugin.last_defined.to_s.split("::").first)
          Plugin.last_defined = nil
          info "Plugin Removed."
        rescue
          raise if $!.is_a? SystemExit
          error "Unable to remove plugin."
        end
      end
      info "Plugin '#{plugin['name']}' processing complete."
    end


    # captures a list of processes running at this moment
    def take_snapshot
      info "Taking a process snapshot"
      ps=%x(ps aux).split("\n")[1..-1].join("\n") # get rid of the header line
      @checkin[:snapshot]=ps
      rescue Exception
        error "unable to capture processes on this server. #{$!.message}"
        return nil
    end

    # Prepares a check-in data structure to hold Plugin generated data.
    def prepare_checkin
      @checkin = { :reports   => Array.new,
                   :alerts    => Array.new,
                   :errors    => Array.new,
                   :summaries => Array.new,
                   :snapshot  => '' }
    end

    def show_checkin(printer = :p)
      send(printer, @checkin)
    end

    #
    # Loads the history file from disk. If the file does not exist,
    # it creates one.
    #
    def load_history
      if !File.exist?(@history_file) || File.zero?(@history_file)
        create_blank_history
      end
      debug "Loading history file..."
      @history = File.open(@history_file) { |file| YAML.load(file) }
      info "History file loaded."
    end

    # creates a blank history file
    def create_blank_history
      debug "Creating empty history file..."
      File.open(@history_file, "w") do |file|
        YAML.dump({"last_runs" => Hash.new, "memory" => Hash.new}, file)
      end
      info "History file created."      
    end    

    # Saves the history file to disk.
    def save_history
      debug "Saving history file..."
      File.open(@history_file, "w") { |file| YAML.dump(@history, file) }
      info "History file saved."
    end

    private
    
    def build_report(plugin_hash, fields)
      { :plugin_id  => plugin_hash['id'],
        :created_at => Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"),
        :fields     => fields,
        :local_filename => plugin_hash['local_filename'], # this will be nil unless it's an ad-hoc plugin
        :origin => plugin_hash['origin'] # [LOCAL|OVERRIDE|nil]
      }
    end

    def urlify(url_name, options = Hash.new)
      return unless @server
      options.merge!(:client_version => Scout::VERSION)
      URI.join( @server,
                "/clients/CLIENT_KEY/#{url_name}.scout".
                  gsub(/\bCLIENT_KEY\b/, @client_key).
                  gsub(/\b[A-Z_]+\b/) { |k| options[k.downcase.to_sym] || k } )
    end
    
    def post(url, error, body, headers = Hash.new, &response_handler)
      return unless url
      request(url, response_handler, error) do |connection|
        post = Net::HTTP::Post.new( url.path +
                                    (url.query ? ('?' + url.query) : ''),
                                    HTTP_HEADERS.merge(headers) )
        post.body = body
        connection.request(post)
      end
    end

    def get(url, error, headers = Hash.new, &response_handler)
      return unless url
      request(url, response_handler, error) do |connection|
        connection.get( url.path + (url.query ? ('?' + url.query) : ''),
                        HTTP_HEADERS.merge(headers) )
      end
    end
    
    def request(url, response_handler, error, &connector)
      response           = nil
      Timeout.timeout(5 * 60, APITimeoutError) do
        http               = Net::HTTP.new(url.host, url.port)
        if url.is_a? URI::HTTPS
          http.use_ssl     = true
          http.ca_file     = File.join( File.dirname(__FILE__),
                                        *%w[.. .. data cacert.pem] )
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER |
                             OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
        end
        response           = no_warnings { http.start(&connector) }
      end
      case response
      when Net::HTTPSuccess, Net::HTTPNotModified
        response_handler[response] unless response_handler.nil?
      else
        error = "Server says: #{response['x-scout-msg']}" if response['x-scout-msg']
        fatal error
        raise SystemExit.new(error)
      end
    rescue Timeout::Error
      fatal "Request timed out."
      exit
    rescue Exception
      raise if $!.is_a? SystemExit
      fatal "An HTTP error occurred:  #{$!.message}"
      exit
    end
    
    def checkin
      @history['last_checkin'] = Time.now.to_i # might have to save the time of invocation and use here to prevent drift
      io   =  StringIO.new
      gzip =  Zlib::GzipWriter.new(io)
      gzip << @checkin.to_json
      gzip.close
      post( urlify(:checkin),
            "Unable to check in with the server.",
            io.string,
            "Content-Type"     => "application/json",
            "Content-Encoding" => "gzip" )
    rescue Exception
      error "Unable to check in with the server."
      debug $!.class.to_s
      debug $!.message
      debug $!.backtrace
    end
    
    
    def no_warnings
      old_verbose = $VERBOSE
      $VERBOSE    = false
      yield
    ensure
      $VERBOSE = old_verbose
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
