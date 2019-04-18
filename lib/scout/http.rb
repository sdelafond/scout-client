require "net/https"
require "uri"

module Scout
  module HTTP
    CA_FILE     = File.join( File.dirname(__FILE__), *%w[.. .. data cacert.pem] )
    VERIFY_MODE = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    # take care of http/https proxy, if specified in command line options
    # Given a blank string, the proxy_uri URI instance's host/port/user/pass will be nil
    # Net::HTTP::Proxy returns a regular Net::HTTP class if the first argument (host) is nil
    def build_http(uri)
      proxy_uri = URI.parse(uri.is_a?(URI::HTTPS) ? @https_proxy : @http_proxy)
      http = Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port, proxy_uri.user, proxy_uri.password).new(uri.host, uri.port)

      if uri.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.ca_file = CA_FILE
        http.verify_mode = VERIFY_MODE        
      end
      http
    end
  end
end
