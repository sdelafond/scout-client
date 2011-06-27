#!/usr/bin/env ruby -wKU

require "pp"

module Scout
  class Command
    class Sign < Command
      HELP_URL = "https://scoutapp.com/info/creating_a_plugin#private_plugins"
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
        res = Net::HTTP.post_form(URI.parse(url),
                                      {'signature' => sig})
        puts "ERROR - Unable to post signature" if !res.is_a?(Net::HTTPOK)
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
        res = Net::HTTP.get_response(URI.parse(url))
        if !res.is_a?(Net::HTTPOK)
          puts "ERROR - Unable to fetch code: #{res.class}."
          return
        end
        res.body
      end
      
      def load_private_key
        private_key_path=File.expand_path("~/.scout/scout_rsa")
        if !File.exist?(private_key_path)
          puts "ERROR - Unable to find the private key at #{private_key_path} for code signing. See #{HELP_URL} for assistance."
          return nil
        else
          begin
            OpenSSL::PKey::RSA.new(File.read(private_key_path))
          rescue
            puts "Error - Found a private key at #{private_key_path}, but unable to load the key:"
            puts $!.message
            puts "See #{HELP_URL} for assistance."
            return nil
          end
        end
      end  # load_private_key
    end
  end
end
