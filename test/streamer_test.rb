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

class StreamerTest < Test::Unit::TestCase
  def test_reports_system_metrics
    stub_history_file
    plugin_ids_stub = []
    system_metric_collectors = [:disk]

    pusher_socket_stub = stub_pusher_socket(:streaming_key_stub)
    PusherClient::Socket.stubs(:new).returns(pusher_socket_stub)
    streamer = Scout::Streamer.new(:history_file_stub, :streaming_key_stub, :chart_id_stub, :pusher_auth_id_stub, :pusher_app_id_stub, :pusher_key_stub, :pusher_user_id_stub, plugin_ids_stub, system_metric_collectors, :hostname_stub, :http_proxy_stub)

    ServerMetrics::Disk.any_instance.stubs(:run).returns(:disk_metric_stub)
    pusher_socket_stub.expects(:send_channel_event).with('private-streaming_key_stub', 'client-server_data', has_entry(:system_metrics, {:disk => :disk_metric_stub})).returns(true)
    streamer.report
  end

  private

  def stub_history_file
    File.stubs(:read).with(:history_file_stub).returns(YAML.dump({:server_metrics => {}}))
    File.stubs(:dirname).with(:history_file_stub).returns('tmp')
  end

  def stub_pusher_socket(streaming_key)
    pusher_socket_stub = stub
    pusher_socket_stub.stubs(:connect).with(true).returns(true)
    pusher_socket_stub.stubs(:subscribe).with("private-#{streaming_key}", { :user_id => :pusher_user_id_stub }).returns(true)
    pusher_socket_stub
  end
end
