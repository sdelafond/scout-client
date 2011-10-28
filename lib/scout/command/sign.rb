#!/usr/bin/env ruby -wKU

require "pp"
require "openssl"
module Scout
  class Command
    class Sign < Command
      HELP_URL    = "https://scoutapp.com/info/creating_a_plugin#private_plugins"
      CA_FILE     = File.join( File.dirname(__FILE__),
                                    *%w[.. .. .. data cacert.pem] )
      VERIFY_MODE = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
      
      def run
        url, *provided_options = @args
        # read the plugin_code from the file specified
        if url.nil? or url == ''
          puts "Please specify the path to the plugin (scout sign /path/to/plugin.rb)"
          return
        end
        
        code=fetch_code(url)
        if code.nil?
          return
        end
        
        private_key = load_private_key
        if private_key.nil?
          return
        end
        
        puts "Signing code..."
        code=code.gsub(/ +$/,'')
        code_signature = private_key.sign( OpenSSL::Digest::SHA1.new, code)
        sig=Base64.encode64(code_signature)
        
        puts "Posting Signature..."
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        if uri.is_a?(URI::HTTPS)
          http.use_ssl = true
          http.ca_file     = CA_FILE
          http.verify_mode = VERIFY_MODE        
        end
        request = Net::HTTP::Post.new(uri.request_uri)
        request.set_form_data({'signature' => sig})
        res = http.request(request)
        if !res.is_a?(Net::HTTPOK)
          puts "ERROR - Unable to post signature" 
          return
        end
        puts "...Success!"
      rescue Timeout::Error
        puts "ERROR - Unable to sign code (Timeout)"
      rescue
        puts "ERROR - Unable to sign code:"
        puts $!
        puts $!.backtrace
      end # run
      
      def fetch_code(url)
        puts "Fetching code..."
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        if uri.is_a?(URI::HTTPS)
          http.use_ssl = true
          http.ca_file     = CA_FILE
          http.verify_mode = VERIFY_MODE
        end
        request = Net::HTTP::Get.new(uri.request_uri)
        res = http.request(request)
        if !res.is_a?(Net::HTTPOK)
          puts "ERROR - Unable to fetch code: #{res.class}."
          return
        end
        res.body
      end
      
      def load_private_key
        private_key_path=File.expand_path("~/.scout/scout_rsa")
        if !File.exist?(private_key_path)
          puts "ERROR - Unable to find the private key at #{private_key_path} for code signing.\nSee #{HELP_URL} for help creating your account's key pair."
          return nil
        else
          begin
            OpenSSL::PKey::RSA.new(File.read(private_key_path))
          rescue
            puts "Error - Found a private key at #{private_key_path}, but unable to load the key:"
            puts $!.message
            puts "See #{HELP_URL} for help creating your account's key pair."
            return nil
          end
        end
      end  # load_private_key
    end
  end
end
