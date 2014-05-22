# Toquen
![A Toque](http://upload.wikimedia.org/wikipedia/commons/thumb/b/bc/William_Orpen_Le_Chef_de_l%27H%C3%B4tel_Chatham%2C_Paris.jpg/97px-William_Orpen_Le_Chef_de_l%27H%C3%B4tel_Chatham%2C_Paris.jpg)

**Toquen** combines [Capistrano 3](http://www.capistranorb.com), [Chef](http://www.getchef.com), and [AWS instance tags](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html) into one bundle of joy.  Instance roles are stored in AWS tags and **Toquen** can suck those out, put them into data bags for chef, and create stages in capistrano.  You can then selectively run chef on individual servers or whole roles that contain many servers with simple commands.

## Installation
Before beginning, you should already understand how [chef-solo](http://docs.opscode.com/chef_solo.html) works and have some cookbooks, roles defined, and at least a folder for data_bags (even if it's empty).  The rest of this guide assumes you have these ready as well as an AWS PEM key and [access credentials](http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSGettingStartedGuide/AWSCredentials.html).

Generally, it's easiest if you start off in an empty directory.  First, create a file named *Gemfile* that contains these lines:

```ruby
source 'http://rubygems.org'
gem 'toquen'
```

Then, create a file named *Capfile* that contains the following line:

```ruby
require 'toquen'
```

And then on the command line execute:

    $ bundle
    $ cap toquen_install

This will create a config directory with a file named *deploy.rb*.  Edit this file, setting the location of your AWS key, AWS credentials, and chef cookbooks/data bags/roles.

Then, in AWS, create an [AWS instance tag](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html) named "Roles" for each instance, using a space separated list of chef roles as the value.  The "Name" tag must also be set or the instance will be ignored.

Then, run:

    $ cap update_roles

This will create a data_bag named *servers* in your data_bags path that contains one item per server name, as well as create stages per server and role for use in capistrano.

## Server Bootstrapping
Bootstrapping a server will perform all of the following:

1. Update all packages (assuming a Debian/Ubuntu system)
1. Sets the hostname to be whatever you set as value for the Name tag in AWS
1. Installs Ruby / RubyGems
1. Install the chef gem
1. Reboot

You can bootstrap a single server by using:

    $ cap server-<server name> bootstrap

Or a all the servers with a given role:

    $ cap <role name> bootstrap

Or on all servers:

    $ cap all bootstrap

A lockfile is created after the first bootstrapping so that the full bootstrap process is only run once per server.

## Running Chef-Solo
You can run chef-solo for a single server by using:

    $ cap server-<server name> cook

Or a all the servers with a given role with:

    $ cap <role name> cook

Or on all servers:

    $ cap all cook

## Updating Roles
If you change the roles of any servers on AWS (or add any new ones) you will need to run:

    $ cap update_roles

This will update the *servers* data_bag as well as the capistrano stages.

## Additional Configuration
If you want to use a different tag name (or you like commas as a delimiter) you can specify your own role extractor by placing the following in either your Capfile or config/deploy.rb:

```ruby
Toquen.config.aws_roles_extractor = lambda { |inst| (inst.tags["MyRoles"] || "").split(",") }
```

By default, instance information is only pulled out of the default region (us-east-1), but you can specify mutiple alternative regions:

```ruby
set :aws_regions, ['us-west-1', 'us-west-2']
```

## View Instances
To see details about your aws instances you can use the **details** cap task.

    $ cap all details

Or for a given role with:

    $ cap <role name> details

Or for a given server with:

    $ cap server-<server name> details

## Open SSH to Current Machine
To allow an SSH connection from your current machine (based on your internet visible IP, as determined using [this method](http://findingscience.com/internet/ruby/2014/05/17/stunning:-determining-your-public-ip.html)), use the open_ssh/close_ssh capistrano tasks.

    $ cap databases open_ssh

And then, when you're finished:

    $ cap databases close_ssh

Or, if you want to do everything in one step:

    $ cap databases open_ssh cook close_ssh

**Note**: You can also use the task *open_port[22]* and *close_port[22]* to open and close SSH (or any other port).