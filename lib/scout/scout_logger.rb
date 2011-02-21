# We use this subclass of Logger in the Scout Agent so we can retrieve all the logged messages at the end of the run.
# This works well only because the Agent is not a long-running process.

require 'logger'

class ScoutLogger < Logger
  attr_reader :messages

  def initialize(*args)
    @messages=[]
    super
  end

  # this is the method that ultimately gets called whenever you invoke info, debug, etc.
  def add(severity, message=nil, progname = nil, &block)
    @messages << "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S ')} ##{$$}] : #{progname}"
    super
  end
end