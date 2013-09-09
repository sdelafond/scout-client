module Scout
  class Environment
    def self.bundler?
      ENV['BUNDLE_BIN_PATH'] && ENV['BUNDLE_GEMFILE']
    end

    def self.rvm?
      ENV['MY_RUBY_HOME'] && ENV['MY_RUBY_HOME'].include?('rvm')
    end

    def self.rvm_path
      rvm_path = `rvm env --path`
      if $?.exitstatus != 0
        raise "Scout is unable to generate a Cron shell script for RVM versions <= 1.12.0. See http://blog.scoutapp.com/articles/2013/06/07/rvm-bundler-and-cron-in-production-round-2 for instructions on building this script manually."
      end
      rvm_path
    end
  end
end
