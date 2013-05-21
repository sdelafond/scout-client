module Scout
  class Environment
    def self.bundler?
      ENV['BUNDLE_BIN_PATH'] && ENV['BUNDLE_GEMFILE']
    end

    def self.rvm?
      ENV['MY_RUBY_HOME'] && ENV['MY_RUBY_HOME'].include?('rvm')
    end

    def self.rvm_path
      `rvm env --path`
    end
  end
end
