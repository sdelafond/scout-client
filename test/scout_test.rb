# These are integration tests -- they require a local instance of the Scout server to run.
# If you only have the Scout Agent gem, these tests will not run successfully.
#
# Scout internal note: See documentation in scout_sinatra for running tests.
#
$VERBOSE=nil
$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require 'test/unit'
require 'lib/scout'
require "pty"
require "expect"

require 'rubygems'
require "active_record"
require "json"          # the data format
require "erb"           # only for loading rails DB config for now
require "logger"
require "newrelic_rpm"

SCOUT_PATH = '../scout'
SINATRA_PATH = '../scout_sinatra'
AGENT_DIR = File.expand_path( File.dirname(__FILE__) ) + '/working_dir/'
PATH_TO_DATA_FILE = File.join AGENT_DIR, 'history.yml'
AGENT_LOG = File.join AGENT_DIR, 'latest_run.log'
PLUGINS_PROPERTIES = File.join AGENT_DIR, 'plugins.properties'
PATH_TO_TEST_PLUGIN = File.expand_path( File.dirname(__FILE__) ) + '/plugins/temp_plugin.rb'

class ScoutTest < Test::Unit::TestCase
  def setup    
    load_fixtures :clients, :plugins, :accounts, :subscriptions, :plugin_metas
    clear_tables :plugin_activities, :ar_descriptors, :summaries
    # delete the existing history file
    File.unlink(PATH_TO_DATA_FILE) if File.exist?(PATH_TO_DATA_FILE)
    File.unlink(AGENT_LOG) if File.exist?(AGENT_LOG)
    File.unlink(PLUGINS_PROPERTIES) if File.exist?(PLUGINS_PROPERTIES)

    Client.update_all "last_checkin='#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    # ensures that fields are created
    # Plugin.update_all "converted_at = '#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    # clear out RRD files
    Dir.glob(SCOUT_PATH+'/test/rrdbs/*.rrd').each { |f| File.unlink(f) }
    @client=Client.find_by_key 'key', :include=>:plugins
    @plugin=@client.plugins.first
    # avoid client limit issues
    assert @client.account.subscription.update_attribute(:clients,100)
  end

  def test_should_checkin_during_interactive_install
    Client.update_all "last_checkin=null"
    res=""
    PTY.spawn("bin/scout -s http://localhost:4567 -d #{PATH_TO_DATA_FILE} install ") do | stdin, stdout, pid |
      begin
        stdin.expect("Enter the Server Key:", 3) do |response|
          assert_not_nil response, "Agent didn't print prompt for server key"
          stdout.puts @client.key # feed the agent the key
          res=stdin.read.lstrip
        end
      rescue Errno::EIO
        # don't care
      end
    end

    assert res.match(/Attempting to contact the server.+Success!/m), "Output from interactive install session isn't right"

    assert_in_delta Time.now.utc.to_i, @client.reload.last_ping.to_i, 100
    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100  
  end
  
  def test_should_run_first_time
    assert_nil @client.last_ping

    scout(@client.key)
    assert_in_delta Time.now.utc.to_i, @client.reload.last_ping.to_i, 100
    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100

    assert_equal 'ping_key', history['directives']['ping_key']
  end

  def test_should_not_run_if_not_time_to_checkin
    # do an initial checkin...should work
    test_should_run_first_time
    
    prev_checkin = @client.reload.last_checkin
    sleep 2
    scout(@client.key)
    assert_equal prev_checkin, @client.reload.last_checkin
  end

  def test_should_run_when_forced
    # do an initial checkin...should work
    test_should_run_first_time
    
    prev_checkin = @client.reload.last_checkin
    sleep 2
    scout(@client.key,'-F')
    assert @client.reload.last_checkin > prev_checkin
  end


  # indirect way of assessing reuse: examining log
  def test_reuse_existing_plan
    test_should_run_first_time

    res=scout(@client.key, '-v -ldebug')
    assert_match "Plan not modified",res
  end

  def test_should_write_log_on_checkin
    assert !File.exist?(AGENT_LOG)
    test_should_run_first_time
    assert File.exist?(AGENT_LOG)
  end

  def test_should_append_to_log_on_ping
    test_should_run_first_time
    assert File.exist?(AGENT_LOG)
    log_file_size=File.read(AGENT_LOG).size
    sleep 1
    scout(@client.key)
    assert File.read(AGENT_LOG).size > log_file_size, "log should be longer after ping"

  end

  def test_should_use_name_option
    scout(@client.key,'--name="My New Server"')
    assert_equal "My New Server", @client.reload.name
  end

  def test_should_not_change_name_when_not_provided
    name=@client.name
    scout(@client.key)
    assert_equal name, @client.reload.name
  end

  def test_should_retrieve_new_plan
  end
  
  def test_should_checkin_even_if_history_file_not_writeable
  end

  def test_should_get_plan_with_blank_history_file
   # Create a blank history file
   File.open(PATH_TO_DATA_FILE, 'w+') {|f| f.write('') }

   scout(@client.key)
   assert_in_delta Time.now.utc.to_i, @client.reload.last_ping.to_i, 100
   assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100
  end
  
  def test_should_generate_error_on_plugin_timeout
  end
  
  
  def test_should_generate_alert
    prev_alerts = Alert.count

    load_average = Plugin.find(1)

    # In the real world, the md5 is taken care of automatically, and private key signing takes place manually.
    # These extra steps are necessary because we have the Sinatra version of the models, not the Rails version.
    new_code="class MyPlugin < Scout::Plugin; def build_report; alert('yo'); end; end"
    load_average.meta.code = new_code
    load_average.meta.save
    load_average.signature=<<EOS
svVV4Qegk2KqqmiHW3ZzlAGFWZSVDPsWn6oCj6hLKWGEvupku7iltk8MLl9O
XIIzzCpkQ1M4izxiQKv+7V9+revh7WJQJDl4xdIL2laYBYRpjHr61YTjCnvw
/aJ1mx/dXHJ6JiYadrAHBIUty/387BAorytIINJppzVre5rWOKyI7ulpC423
3v+qY6ZcpzUCvxDTI82x13xNcAfN6HkTE7RUtwhkaeKmJChEIwhiShdBirTP
dDLxK2GuTGFCn5PWJWvbryQJIjI6CbLGwxq8D8FaOiq6FojfjtsDS3oyR/Vl
2EHBYcHwyZm6WcBypyXblUeqBfZLezfqF1QdYP76HA==
EOS
    load_average.code_md5_signature=Digest::MD5.hexdigest(new_code)
    load_average.save
    
    scout(@client.key,'-F')

    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100
    assert_equal prev_alerts + 1, Alert.count
  end
  
  def test_should_generate_report
    prev_checkin = @client.reload.last_checkin
    scout(@client.key,'-F')
    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100
    load_average = Plugin.find(1)
    assert_in_delta Time.now.utc.to_i, load_average.last_reported_at.to_i, 100
  end

  def test_should_set_config_path
    assert @client.config_path.blank?
    test_should_run_first_time
    @client.reload
    assert_equal AGENT_DIR, @client.config_path+"/"
  end

  def test_should_generate_summaries
    
  end

  def test_memory_should_be_stored
    
  end

  def test_client_version_is_set
    assert_nil @client.last_ping
    @client.update_attribute(:version,nil)
    scout(@client.key)
    assert_equal Gem::Version.new(Scout::VERSION), @client.reload.version
  end

  def test_client_hostname_is_set
    assert_nil @client.hostname
    scout(@client.key)
    assert_equal `hostname`.chomp, @client.reload.hostname
  end


  def test_corrupt_history_file
    File.open(PATH_TO_DATA_FILE,"w") do |f|
      f.write <<-EOS
---
memory: {}
  497081-Nginx monitoring: {}
EOS

    end
    scout(@client.key)

    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100, "should have checked in even though history file is corrupt"

    corrupt_history_path=File.join AGENT_DIR, 'history.corrupt'
    assert File.exist?(corrupt_history_path), "Should have backed up corrupted history file"
    File.delete(corrupt_history_path) # just cleanup
  end

  def test_empty_history_file
    # #there's no good way of testing this without complicated m
    # File.open(PATH_TO_DATA_FILE,"w") {|f| f.write "" }
    # #need to mock Scout::Server create_blank_history to make the file EMPTY for this test to be effective
    # scout(@client.key,"-v -ldebug",true)
  end

  ####################
  ### Test-Related ###
  ####################
  def test_runs_in_test_mode
    code=<<-EOC
      class StarterPlugin < Scout::Plugin
        def build_report
          report(:answer=>42)
        end
      end
    EOC

    run_scout_test(code) do |res|
      assert ":fields=>{:answer=>42}", res
    end
  end


  def test_embedded_options_in_test_mode
    code=<<-EOC
      class StarterPlugin < Scout::Plugin
        OPTIONS=<<-EOS
          lunch:
            label: Lunch Time
            default: 12
        EOS
        def build_report
          report(:lunch_is_at => option(:lunch))
        end
      end
    EOC

    run_scout_test(code) do |res|
      assert_match ":fields=>{:lunch_is_at=>12}", res
    end
  end

  def test_command_line_options_in_test_mode
    code=<<-EOC
      class StarterPlugin < Scout::Plugin
        OPTIONS=<<-EOS
          lunch:
            label: Lunch Time
            default: 12
        EOS
        def build_report
          report(:lunch_is_at => option(:lunch))
        end
      end
    EOC

    run_scout_test(code, 'lunch=13') do |res|      
      assert_match ':fields=>{:lunch_is_at=>"13"', res 
    end
  end

  # Needed to ensure that malformed embedded options don't bork the agent in test mode
  def test_invalid_embedded_options_in_test_mode
    code=<<-EOC
      class StarterPlugin < Scout::Plugin
        OPTIONS=<<-EOS
          invalid yaml, oh noes!
        EOS

        def build_report
          report(:answer=>42)
        end
      end
    EOC
    run_scout_test(code) do |res|
      assert_match "Problem parsing option definition in the plugin code (ignoring and continuing)", res
      assert_match ":fields=>{:answer=>42}", res
    end
  end

  def test_plugin_properties

    code=<<-EOC
      class LookupTest < Scout::Plugin
        OPTIONS=<<-EOS
          foo:
            default: 0
        EOS
        def build_report
          report :foo_value=>option(:foo)
        end
      end
    EOC

    run_scout_test(code, 'foo=13') do |res|
      assert_match ':fields=>{:foo_value=>"13"', res
    end

    properties=<<-EOS
# this is a properties file
myfoo=99
mybar=100
    EOS

    properties_path=File.join(AGENT_DIR,"plugins.properties")
    File.open(properties_path,"w") {|f| f.write properties}

    run_scout_test(code, 'foo=lookup:myfoo') do |res|
      assert_match ':fields=>{:foo_value=>"99"', res
    end

    #cleanup
    File.unlink(properties_path)
  end

  def test_plugin_override
    override_path=File.join(AGENT_DIR,"#{@plugin.id}.rb")
    code=<<-EOC
      class OverrideTest < Scout::Plugin
        def build_report; report(:foo=>99);end
      end
    EOC
    File.open(override_path,"w"){|f|f.write(code)}

    scout(@client.key)

    report=YAML.load(@plugin.reload.last_report_raw)
    assert report["foo"].is_a?(Array)
    assert_equal 99, report["foo"].first
    File.delete(override_path)
  end

  #def test_plugin_override_removed
  #  test_plugin_override
  #
  #  # have to clear the RRD files so it doesn't complain about checking in to quickly
  #  Dir.glob(SCOUT_PATH+'/test/rrdbs/*.rrd').each { |f| File.unlink(f) }
  #  @plugin.rrdb_file.create_database(Time.now, [])
  #  scout(@client.key, "-F")
  #
  #  report=YAML.load(@plugin.reload.last_report_raw)
  #  assert_nil report["foo"], "report shouldn't contain 'foo' field from the override"
  #  assert report["load"].is_a?(Array)
  #  assert_equal 2, report["load"].first
  #end

  def test_local_plugin
    plugin_count=@client.plugins.count
    local_path=File.join(AGENT_DIR,"my_local_plugin.rb")
    code=<<-EOC
      class LocalPluginTest < Scout::Plugin
        def build_report; report(:answer=>42);end
      end
    EOC
    File.open(local_path,"w"){|f|f.write(code)}

    scout(@client.key)

    assert_equal plugin_count+1, @client.reload.plugins.count, "there should be one additional plugin records -- created from the local plugin"

    File.delete(local_path)
  end


  def test_streamer_plugin_compilation
    # redefine the trigger! method, so the streamer doesn't loop indefinitely. We can't just mock it, because
    # we need to set the $continue_streaming=false
    Pusher::Channel.module_eval do
      alias orig_trigger! trigger!
      def trigger!(event_name, data, socket=nil)
        $streamer_data = data
        $continue_streaming=false
      end
    end
    plugins=[]
    acl_code="class AclPlugin < Scout::Plugin;def build_report; report(:value=>1);end;end"
    acl_sig=<<EOS
QT/IYlR+/3h0YwBAHJeFz4HRFlisocVGorafNYJSYJC5RaUKqxu3dM+bOU4P
mQ5SmAt1mtXD5BJy2MeHam7Y8HAiWJbDBB318feZrC6xI2amu1b1/YMUyY8y
fMXS9z8J+ABsFIyV26av1KLxU1EHxi9iKxPwMg0HKJhTBStX4uIyncr/+ZSS
QKywEwPIPihFFyh9B2Z5WVSHtGcZG9CXDa20hrbQoNutOTniTkr00evBItYL
FN4L0F0ApIjTTkZW2vjzNR59j8HfZ7zrPfy33VhJkyAS0o9nQt5v0J5wKHj1
c3egj/Ffn/zSWZ1cTf3VSpfrGKUAlyB9KphZeYv2Og==
EOS
    plugins << create_plugin(@client, "AclPlugin_1", acl_code, acl_sig)

    code="class XYZPlugin < Scout::Plugin;def build_report; report(:value=>2);end;end"
    sig=<<EOS
6cNcDCM2GWcoT1Iqri+XFPgAiMxQaf0b8kOi4KKafNVD94cPkcy6OknNeQUM
v6GYcfGCAsiZvnjl/2wsqjvrAl/zyuSW/s5YLsjxca1LEvhkyxbpnDGuj32k
3IuWKQ6JuEbmPXPP1aFsosOm7dbTCrjEn1fDQWAzmfCwznHV3MiqzvPD2D9g
7gtxXcblNP6hm7A6AlBzP0hwYORR//gpLLGtmT5ewltHUj9aSUY0GQle3lvH
/uzBDoV1x6mEYR2jPO5QQxL3BvTBvpC06ec8M/ZWbO9IwA7/DOs+vYfngxlp
jbtpAK9QCaAalKy/Z29os/7aViHy9z9IVCpC/z3MDA==
EOS
    plugins << create_plugin(@client, "XYZ Plugin", code, sig)

    plugins << create_plugin(@client, "AclPlugin_2", acl_code, acl_sig)

    scout(@client.key) # to write the initial history file. Sinatra MUST be running
    $continue_streaming = true # so the streamer will run once
    streamer=Scout::Streamer.new("http://none", "bogus_client_key", PATH_TO_DATA_FILE, [@client.plugins.first.id]+plugins.map(&:id), "bogus_streaming_key",nil) # for debugging, make last arg Logger.new(STDOUT)
    res = $streamer_data # $streamer_data is set in the Channel.trigger! method we temporarily defined above

    assert res.is_a?(Hash)
    assert res[:plugins].is_a?(Array)
    assert_equal 4, res[:plugins].size
    assert_equal 2, res[:plugins][0][:fields][:load]
    assert_equal 1, res[:plugins][1][:fields][:value]
    assert_equal 2, res[:plugins][2][:fields][:value]
    assert_equal 1, res[:plugins][3][:fields][:value]

    Pusher::Channel.module_eval do
      alias trigger! orig_trigger!
    end
  end

  # test streamer starting and stopping
  def test_streamer_process_management
    streamer_pid_file = File.join(AGENT_DIR, "scout_streamer.pid")

    test_should_run_first_time

    assert !File.exist?(streamer_pid_file)

    assert @client.update_attribute(:streamer_command, "start,abc,1,3")
    scout(@client.key)
    assert File.exist?(streamer_pid_file)
    process_id = File.read(streamer_pid_file).to_i
    assert process_running?(process_id)
    assert_nil @client.reload.streamer_command

    assert @client.update_attribute(:streamer_command, "stop")
    scout(@client.key)
    assert !File.exist?(streamer_pid_file)
    sleep 2 # give process time to shut down
    assert !process_running?(process_id)
    assert_nil @client.reload.streamer_command
  end


  ######################
  ### Helper Methods ###
  ######################
  
  # Runs the scout command with the given +key+ and +opts+ string (ex: '-F').
  def scout(key, opts = nil, print_output=false)
    opts = "" unless opts
    cmd= "bin/scout #{key} -s http://localhost:4567 -d #{PATH_TO_DATA_FILE} #{opts} 2>&1"
    puts "command: #{cmd}" if print_output
    output=`#{cmd}`
    puts output if print_output
    output
  end

  # you can use this, but you have to create the plugin file and clean up afterwards.
  # Or, you can use the blog version below
  def scout_test(path_to_test_plugin, opts = String.new)
    `bin/scout test #{path_to_test_plugin} -d #{PATH_TO_DATA_FILE} #{opts}`
  end

  # The preferred way to test the agent in test mode. This creates a plugin file with the code you provide,
  # runs the agent in test mode, and cleans up the file.
  def run_scout_test(code,opts=String.new)
    File.open(PATH_TO_TEST_PLUGIN,"w") do |file|
      file.write(code)
    end

    yield scout_test(PATH_TO_TEST_PLUGIN, opts)

    ensure
      File.unlink(PATH_TO_TEST_PLUGIN)
  end


  def history
    YAML.load(File.read(PATH_TO_DATA_FILE))
  end

  def process_running?(pid)
    begin
      Process.getpgid( pid )
      true
    rescue Errno::ESRCH
      false
    end
  end

  # Establishes AR connection
  def self.connect_ar
    # ActiveRecord configuration
    begin
      $LOAD_PATH << File.join(SCOUT_PATH,'app/models')
      # get an ActiveRecord connection
      db_config_path=File.join(SCOUT_PATH,'config/database.yml')
      db_config=YAML.load(ERB.new(File.read(db_config_path)).result)
      db_hash=db_config['test']
      # Store the full class name (including module namespace) in STI type column
      # For triggers - before, just the class name and not the module name was stored,resulting in errors in the Rails
      # app.
      ActiveRecord::Base.store_full_sti_class = true
      ActiveRecord::Base.establish_connection(db_hash)
      # scout models and local models

      require SINATRA_PATH + '/lib/ar_models.rb'

      ActiveRecord::Base.default_timezone = :utc
      
      puts "Established connection to Scout database :-)"
      puts "  #{Account.count} accounts there (sanity check)"
    end
  end
  
  # ghetto fixture support
  def load_fixtures(*table_names)
    clear_tables(*table_names)
    table_names.each do |table_name|
      path = "#{SCOUT_PATH}/test/fixtures/#{table_name}.yml"
      model_name = ActiveSupport::Inflector.classify table_name
      model_class = ActiveRecord.const_get(model_name)

      data = YAML.load_file(path)
      data.each do |key, value_hash|
        model_instance = model_class.new
        model_instance.id = key.hash if !value_hash.has_key?(:id) # accounting for named foreign keys in fixtures, part 1
        value_hash.each_pair do |k,v|
          if model_instance.respond_to?(k+"_id") # accounting for named foreign keys in fixtures, part 2
            model_instance.send "#{k}_id=",v.hash
          else
            model_instance.send "#{k}=",v
          end
        end
        model_instance.save
      end
    end
  end

  def clear_tables(*tables)
    tables.each do |table|
      ActiveRecord::Base.connection.execute("truncate table #{table}")
    end    
  end

  # see scout's rake plugin:sign task to create the signatre
  def create_plugin(client,name, code, signature)
    p=client.plugins.create(:name=>name)
    PluginMeta.create(:plugin=>p)
    p.meta.code=code
    p.code_md5_signature=Digest::MD5.hexdigest(code)
    p.signature=signature
    p.save
    p.meta.save
    puts "There was a problem creating '#{name}' plugin: #{p.errors.inspect}" if p.errors.any?
    p
  end

end

# Connect to AR before running
ScoutTest::connect_ar

