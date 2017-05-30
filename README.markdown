# Pingdom Server Monitoring Agent

[Scout](https://server.pingdom.com) is an easy-to-use hosted server monitoring service. The `scout` Ruby gem reports metrics to our service. The agent runs plugins, configured via the Scout web interface, to monitor a server. [View a list of available plugins on our website](https://server.pingdom.com/plugin_urls) and [their source on Github](https://github.com/scoutserver/scout-plugins). 

## Installing

Scout requires Ruby, and is installed via Ruby Gems:

    $ gem install scout


## First run from the command line:

    $ scout KEY

`KEY` is the identification key assigned by your account at https://server.pingdom.com. When run from the command line, scout should print "success." If not, run in verbose mode to see what the problem is:

    $ scout KEY -v


## Scout is normally run through cron

After you've successfully run Scout from the command line, you should configure it to run every minute via cron. This is how Scout is designed to run on an ongoing basis. Your contab will typically look like this:

    * * * * *  deploy /usr/bin/scout KEY

... assuming you are using the global crontab, and "deploy" is the user running Scout.


## For a full list of options:

    $ scout --help

## Troubleshooting

The `scout troubleshoot` command provides useful troubleshooting information (log of the last run, environment information, and the list of gems).

Extensive help is available via our website (https://server.pingdom.com) and while installing the agent via the Scout web UI.


## Local plugin testing:

    $ scout [OPTIONS] test PATH_TO_PLUGIN [PLUGIN_OPTIONS]

`PATH_TO_PLUGIN` is the file system path to a Ruby file that contains a Scout plugin.

`PLUGIN_OPTIONS` are one or more options in the form:

    key1=val1 key2=val2

These options will be used for the plugin run. [Lean more about creating your own plugins](https://server-monitor.readme.io/docs/custom-plugins).

## Credits / Contact

Contact support.server@pingdom.com with questions.

Primary maintainers: Andre Lewis (andre.lewis@pingdom.com)

