$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require 'test/unit'
require 'lib/scout'


require 'rubygems'
require "active_record"  # the order seems to be very touchy -- needs to be after sinatra and before json
require "json"          # the data format
require "erb"           # only for loading rails DB config for now
require "logger"

SCOUT_PATH = '../scout'
SINATRA_PATH = '../scout_sinatra'

# TODO
# - provide directory for storing history / pid file ... put in test/scout_data ... ignore the contents
# - only connect to ar once

class ScoutTest < Test::Unit::TestCase
  def setup    
    connect_ar
    load_fixtures :clients, :plugins, :accounts, :subscriptions
    clear_tables :plugin_activities, :ar_descriptors, :summaries
    # line below requires a number of dependencies...leaving off for now...
    # Plugin.all.each(&:reset_rrdb)
    Client.update_all "last_checkin='#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    # ensures that fields are created
    Plugin.update_all "converted_at = '#{5.days.ago.strftime('%Y-%m-%d %H:%M')}'"
    @client=Client.find_by_key 'key', :include=>:plugins
    @plugin=@client.plugins.first
    # avoid client limit issues
    assert @client.account.subscription.update_attribute(:clients,100)
  end

  # def teardown
  # end

  # def test_command_creation
  #   c = Scout::Command::Test.new({},['test/plugins/disk_usage.rb'])
  #   assert c.run
  # end
  
  # Holding off...not sure how to pass thru inputs to STDIN
  def test_should_run_install

  end
  
  def test_should_run_first_time
    assert_nil @client.last_ping
    
    # c = Scout::Command.dispatch([@client.key,"-s", "http://localhost:4567" ])
    `bin/scout #{@client.key} -s http://localhost:4567`
    assert_in_delta Time.now.utc.to_i, @client.reload.last_ping.to_i, 100
    assert_in_delta Time.now.utc.to_i, @client.reload.last_checkin.to_i, 100
  end
  
  def test_should_not_run_if_not_time_to_checkin
    # do an initial checkin...should work
    test_should_run_first_time
    
    prev_checkin = @client.reload.last_checkin
    sleep 2
    `bin/scout #{@client.key} -s http://localhost:4567`
    assert_equal prev_checkin, @client.reload.last_checkin
  end
  
  def test_should_run_when_forced
    # do an initial checkin...should work
    test_should_run_first_time
    
    prev_checkin = @client.reload.last_checkin
    sleep 2
    `bin/scout #{@client.key} -s http://localhost:4567 -F`
    assert @client.reload.last_checkin > prev_checkin
  end
  
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
    
  end
  
  def test_should_generate_error_on_plugin_timeout
    
  end
  
  def test_should_generate_error
    
  end
  
  def test_should_generate_report
    
  end
  
  def test_should_generate_process_list
    
  end
  
  def test_should_generate_summaries
    
  end

  # def test_dispatch
  #   c = Scout::Command.dispatch([@client.key, "-s", "http://localhost:4567", "--verbose", ])
  # end

  ####################
  ### Test-Related ###
  ####################
  
  def test_memory_should_be_stored
    
  end
  
  def test_embedded_options_are_read
    
  end
  
  ######################
  ### Helper Methods ###
  ######################

  # Establishes AR connection
  def connect_ar

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



