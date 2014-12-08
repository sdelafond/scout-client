require 'test/unit'
begin
  require 'pry'
rescue LoadError
  # not using pry
end
# must be loaded after 
$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/..' )
require 'lib/scout'
require 'mocha/setup'
require 'pusher-client'
require 'timecop'

class StreamerTest < Test::Unit::TestCase
  def setup
    # in case the test needs a plugin to run
    stub_history_file({"old_plugins" => [{
      'id' => 123,
      'name' => 'test_plugin',
      'code' => "class TestPlugin < Scout::Plugin; def build_report; report(:value => 1); end; end;"
    }]})

    # add the plugin id or system metric collector to these per the test's needs
    @plugin_ids = []
    @system_metric_collectors = []

    # stub the pusher socket. create expectations on this stub
    @pusher_socket_stub = stub_pusher_socket(:streaming_key_stub)
    PusherClient::Socket.stubs(:new).returns(@pusher_socket_stub)
  end

  def test_reports_system_metrics
    @system_metric_collectors << :disk

    streamer = Scout::Streamer.new(:history_file_stub, :streaming_key_stub, :chart_id_stub, :pusher_auth_id_stub, :pusher_app_id_stub, :pusher_key_stub, :pusher_user_id_stub, @plugin_ids, @system_metric_collectors, :hostname_stub, :http_proxy_stub)

    ServerMetrics::Disk.any_instance.stubs(:run).returns(:disk_metric_stub)
    @pusher_socket_stub.expects(:send_channel_event).with('private-streaming_key_stub', 'client-server_data', has_entry(:system_metrics, {:disk => :disk_metric_stub})).returns(true)
    streamer.report
  end

  def test_returns_a_message_if_the_plugin_times_out
    @plugin_ids << 123
    streamer = Scout::Streamer.new(:history_file_stub, :streaming_key_stub, :chart_id_stub, :pusher_auth_id_stub, :pusher_app_id_stub, :pusher_key_stub, :pusher_user_id_stub, @plugin_ids, @system_metric_collectors, :hostname_stub, :http_proxy_stub)

    Scout::Plugin.any_instance.stubs(:run).raises(Scout::PluginTimeoutError)
    @pusher_socket_stub.expects(:send_channel_event).with('private-streaming_key_stub', 'client-server_data', has_entry(:plugins, [{:fields=>{}, :name=>"test_plugin", :id=>123, :class=>"TestPlugin", :message=>"took too long to run", :duration=>0}])).returns(true)
    Timecop.freeze do # so that duration consistently reports 0
      streamer.report
    end
  end

  def test_stops_running_a_plugin_if_it_times_out_twice
    @plugin_ids << 123
    streamer = Scout::Streamer.new(:history_file_stub, :streaming_key_stub, :chart_id_stub, :pusher_auth_id_stub, :pusher_app_id_stub, :pusher_key_stub, :pusher_user_id_stub, @plugin_ids, @system_metric_collectors, :hostname_stub, :http_proxy_stub)

    # test that the plugin only runs twice
    Scout::Plugin.any_instance.expects(:run).raises(Scout::PluginTimeoutError).twice
    @pusher_socket_stub.expects(:send_channel_event).with('private-streaming_key_stub', 'client-server_data', has_entry(:plugins, [{:fields=>{}, :name=>"test_plugin", :id=>123, :class=>"TestPlugin", :message=>"took too long to run", :duration=>0}])).returns(true).times(3)
    Timecop.freeze do # so that duration consistently reports 0
      3.times { streamer.report }
    end
  end

  private

  def stub_history_file(history = {})
    history = {:server_metrics => {},
               'last_runs' => {},
               'memory' => {}}.merge(history)
    File.stubs(:read).with(:history_file_stub).returns(YAML.dump(history))
    File.stubs(:dirname).with(:history_file_stub).returns('tmp')
  end

  def stub_pusher_socket(streaming_key)
    pusher_socket_stub = stub
    pusher_socket_stub.stubs(:connect).with(true).returns(true)
    pusher_socket_stub.stubs(:subscribe).with("private-#{streaming_key}", { :user_id => :pusher_user_id_stub }).returns(true)
    pusher_socket_stub
  end
end
