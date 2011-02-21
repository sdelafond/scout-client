#!/usr/bin/env ruby -wKU

require "pp"

module Scout
  class Command
    class Troubleshoot < Command
      def initialize(options, args)
        @contents=[]
        super
      end

      def run
        puts "Gathering troubleshooting information about your Scout install ... "

        heading "Scout Info"
        bullet "History file", history
        bullet "Version", Scout::VERSION

        heading "Latest Log"
        contents=File.read(log_path) rescue "Log not found at #{log_path}"
        text contents

        heading "Rubygems Environment"
        text `gem env`

        heading "Ruby info"
        bullet "Path to executable", `which ruby`
        bullet "Version", `ruby -v`
        bullet "Ruby's internal path",  $:.join(', ')

        heading "Installed Gems"
        text `gem list --local`

        heading "History file Contents"
        contents=File.read(history) rescue "History not found at #{log_path}"
        text contents

        heading "Agent directory Contents"
        text `ls -la #{config_dir}`

        puts "Done"

        puts @contents.join("\n")

      end
    end

    private
    def heading(s)
      @contents += ["",s,"**************************************************************************************************",""]
    end

    def bullet(label,s)
      @contents << " - #{label} :  #{s.chomp}"
    end

    def text(s)
      @contents << s
    end

  end
end
