# Scout Server Monitoring Agent

[Scout](https://scoutapp.com) is an easy-to-use hosted server monitoring service. The `scout` Ruby gem reports metrics to our service.

## Installing

Install the Scout gem:

    $ gem install scout

Then simply run:

    $ scout

to run the installation wizard. You'll need your server key, provided via Scout's web UI, to continue. Scout's web UI also provides additional troubleshooting and Ruby installation instructions.

## Running the Scout Agent

The Scout agent has several modes of operation and commands.  The normal, intended usage is through a scheduled interval with no output.

Normal checkin with server:

    $ scout [OPTIONS] SERVER_KEY

Install:

    $ scout
    $ scout [OPTIONS] install

Local plugin testing:

    $ scout [OPTIONS] test PATH_TO_PLUGIN [PLUGIN_OPTIONS]


`SERVER_KEY` is the identification key assigned by your account at http://scoutapp.com

`PATH_TO_PLUGIN` is the file system path to a Ruby file that contains a Scout plugin.

`PLUGIN_OPTIONS` are one or more options in the form:

    key1=val1 key2=val2
    
These options will be used for the plugin run.

## Setting up in Cron

Configure Scout to run every minute. Typically, this will look like:

    * * * * *  deploy /usr/bin/scout SERVER_KEY

It's often helpful to log the output to a file. To do so:

    * * * * *  deploy /usr/bin/scout SERVER_KEY > /path/to/anywhere/scout.out 2>&1

For additional help, please visit http://scoutapp.com.

## Credits / Contact

Contact support@scoutapp.com with questions.

Primary maintainers: Andre Lewis (andre@scoutapp.com) and Derek Haynes (derek@scoutapp.com)

Many thanks to James Edward Gray II, Charles Brian Quinn, and Matt Todd for early work on the Scout agent!
