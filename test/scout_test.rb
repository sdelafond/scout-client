# These are integration tests -- they require a local instance of the Scout server to run.
# If you only have the Scout Agent gem, these tests will not run successfully.
#
# Scout internal note: See documentation in scout_sinatra for running tests.
#
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

SCOUT_PATH = '../scout'
SINATRA_PATH = '../scout_sinatra'
PATH_TO_DATA_FILE = File.expand_path( File.dirname(__FILE__) ) + '/history.yml'

class ScoutTest < Test::Unit::TestCase
  def setup    
    load_fixtures :clients, :plugins, :accounts, :subscriptions
    clear_tables :plugin_activities, :ar_descriptors, :summaries
    # delete the existing history file
    File.unlink(PATH_TO_DATA_FILE) if File.exist?(PATH_TO_DATA_FILE)
    Client.update_all "last_checkin='#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    # ensures that fields are created
    # Plugin.update_all "converted_at = '#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    # clear out RRD files
    Dir.glob(SCOUT_PATH+'/test/rrdbs/db/*.rrd').each { |f| File.unlink(f) }
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

  # Needed to ensure that malformed embedded options don't bork the agent in test mode
  def test_embedded_options_are_invalid
    
  end
  
  def test_plugin_does_not_inherit_from_scout_plugin
    
  end
  
  def test_reuse_existing_plan
    
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
    load_average.code = "class MyPlugin < Scout::Plugin; def build_report; alert('yo'); end; end"
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
  
  def test_should_generate_process_list
    
  end
  
  def test_should_generate_summaries
    
  end

  def test_memory_should_be_stored
    
  end

  ####################
  ### Test-Related ###
  ####################
  
  def test_embedded_options_are_read
    
  end
  
  ######################
  ### Helper Methods ###
  ######################
  
  # Runs the scout command with the given +key+ and +opts+ string (ex: '-F').
  def scout(key, opts = String.new)
    `bin/scout #{key} -s http://localhost:4567 -d #{PATH_TO_DATA_FILE} #{opts}`
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
end

# Connect to AR before running
ScoutTest::connect_ar

