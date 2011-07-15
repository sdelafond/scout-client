#!/usr/bin/env ruby -wKU

module Scout
  class Command
    class Stream < Command
      def run
        @scout = Scout::Streamer.new(history, log)
      end
    end
  end
end
