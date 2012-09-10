# Scout Server Monitoring Agent

[Scout](https://scoutapp.com) is an easy-to-use hosted server monitoring service. The `scout` Ruby gem reports metrics to our service. The agent runs plugins, configured via the Scout web interface, to monitor a server. [View a list of available plugins on our website](https://scoutapp.com/plugin_urls) and [their source on Github](http://github.com/scoutapp/scout-plugins). 

## Installing

Install the Scout gem:

    $ gem install scout

Then simply run:

    $ scout

to start the installation wizard. You'll need your server key, provided via Scout's web UI, to continue. Scout's web UI also provides additional troubleshooting and Ruby installation instructions.

## Running the Scout Agent

The Scout agent has several modes of operation and commands.  The normal, intended usage is through a scheduled interval with no output.

Normal checkin with server:

    $ scout [OPTIONS] SERVER_KEY

`SERVER_KEY` is the identification key assigned by your account at http://scoutapp.com.

Install:

    $ scout
    $ scout [OPTIONS] install
    
Local plugin testing:

    $ scout [OPTIONS] test PATH_TO_PLUGIN [PLUGIN_OPTIONS]

`PATH_TO_PLUGIN` is the file system path to a Ruby file that contains a Scout plugin.

`PLUGIN_OPTIONS` are one or more options in the form:

    key1=val1 key2=val2
    
These options will be used for the plugin run. [Lean more about creating your own plugins](https://scoutapp.com/info/creating_a_plugin).

For a full list of options:

    scout --help

## Setting up in Cron

Configure Scout to run every minute. Typically, this will look like:

    * * * * *  deploy /usr/bin/scout SERVER_KEY
    
## Troubleshooting

The `scout troubleshoot` command provides useful troubleshooting information (log of the last run, environment information, and the list of gems).

Extensive help is available via our website (http://scoutapp.com) and while installing the agent via the Scout web UI.

## Credits / Contact

Contact support@scoutapp.com with questions.

Primary maintainers: Andre Lewis (andre@scoutapp.com) and Derek Haynes (derek@scoutapp.com)

Many thanks to James Edward Gray II, Charles Brian Quinn, and Matt Todd for early work on the Scout agent!
