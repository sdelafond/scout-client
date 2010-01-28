$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require 'test/unit'
require 'lib/scout'


require 'rubygems'
require "active_record"  # the order seems to be very touchy -- needs to be after sinatra and before json
require "json"          # the data format
require "erb"           # only for loading rails DB config for now
require "logger"

class ScoutTest < Test::Unit::TestCase
  # def setup
  # end

  # def teardown
  # end

  LOGGER =nil

  def test_command_creation
    c = Scout::Command::Test.new({},['test/plugins/disk_usage.rb'])
    assert c.run
  end

  def test_dispatch
    connect_ar
  #  c = Scout::Command.dispatch(['key', "-s", "http://localhost:4567", "--verbose", ])
  end




  def connect_ar
    scout_path = '../scout'

    # ActiveRecord configuration
    begin
      $LOAD_PATH << File.join(scout_path,'app/models')
      # get an ActiveRecord connection
      db_config_path=File.join(scout_path,'config/database.yml')
      db_config=YAML.load(ERB.new(File.read(db_config_path)).result)
      db_hash=db_config['test']
      # Store the full class name (including module namespace) in STI type column
      # For triggers - before, just the class name and not the module name was stored,resulting in errors in the Rails
      # app.
      ActiveRecord::Base.store_full_sti_class = true
      ActiveRecord::Base.establish_connection(db_hash)
      # scout models and local models

      Dir.glob(scout_path+"/app/models/*.rb").each do |m|
        require(m)
      end

      ActiveRecord::Base.logger = LOGGER
      ActiveRecord::Base.default_timezone = :utc
#      LOGGER   = Logger.new(File.join(MY_DIR,'log', "#{Sinatra::Application.environment}.log"))
      puts "Established connection to Scout database :-)"
      puts "  #{Account.count} accounts there (sanity check)"
      # the line below needs to come AFTER the logger is set in ActiveRecord
#      require "#{scout_path}/config/initializers/rrdtool.rb"
#      RRDB.logger = LOGGER.dup
#      RRDB.logger.level = Logger::DEBUG
    end
  end
end



