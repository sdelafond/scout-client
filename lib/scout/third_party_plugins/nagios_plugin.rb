module Scout
  class NagiosPlugin < Scout::Plugin
    attr_accessor :cmd

    # The command, with arguments, to run a nagios plugin.
    # Ex: /usr/lib/nagios/plugins/check_procs -w 150 -c 200
    def initialize(cmd)
      self.cmd = cmd
    end

    def build_report
      #return if !sanity_check

      # We only support parsing the first line of nagios plugin output
      IO.popen("#{cmd}") {|io| @nagios_output = io.readlines[0] }
      
      # Use exit status integer for OK/WARN/ERROR/CRIT status
      plugin_status = $?.exitstatus

      data = parse_nagios_output(@nagios_output)
      report(data.merge({:status => plugin_status}))
    end

    # todo - need to remove arguments
    def sanity_check
      puts cmd
      if cmd.nil?
        error("The nagios_plugin_command is not defined", "You must configure the full path of the nagios plugin command in nagios_plugin_command")
      elsif !File.exists?(cmd)
        error("The nagios_plugin_command file does not exist", "The nagios_plugin_command file does not exist.")
      elsif !File.executable?(cmd)
        error("Can not execute nagios_plugin_command", "The nagios_plugin_command file is not executable.")
      end
      data_for_server[:errors].any? ? false : true
    end

    def parse_nagios_output(output)
      text_field, perf_field = output.split('|',2)
      perf_data = {}
      if !perf_field.nil? && perf_field.strip!.length
        # Split the perf field
        # 1) on spaces
        # 2) up to the first 10 metrics
        # 3) split each "k=v;;;;" formatted metric into a key and value
        # 4) add the key to perf_data, and the digits from the value
        perf_field.split(" ")[0,10].inject(perf_data) {|r,e| k,v=e.split('=')[0,2]; r[k] = v.slice!(/^[\d.]*/).to_f if k && v; r}
      end

      #TODO - Allow ability to define regex captures of the text field numerical values as metrics
      text_data = {}

      return perf_data.merge(text_data)
    end

  end
end