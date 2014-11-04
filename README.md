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

```shell
bundle
cap toquen_install
```

This will create a config directory with a file named *deploy.rb*.  Edit this file, setting the location of your AWS key, AWS credentials, and chef cookbooks/data bags/roles.  If your servers are in a region (or regions) other than us-east-1, then you'll need to set the region as [described below](#additional-configuration).

Then, in AWS, create an [AWS instance tag](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Using_Tags.html) named "Roles" for each instance, using a space separated list of chef roles as the value.  The "Name" tag must also be set or the instance will be ignored.

Then, run:

```shell
cap update_roles
```

This will create a data_bag named *servers* in your data_bags path that contains one item per server name, as well as create stages per server and role for use in capistrano.

## Server Bootstrapping
Bootstrapping a server will perform all of the following:

1. Update all packages (assuming a Debian/Ubuntu system)
1. Sets the hostname to be whatever you set as value for the Name tag in AWS
1. Installs Ruby / RubyGems
1. Install the chef gem
1. Reboot

You can bootstrap a single server by using:

```shell
cap server-<server name> bootstrap
```

Or a all the servers with a given role:

```shell
cap <role name> bootstrap
```

Or on all servers:

```shell
cap all bootstrap
```

A lockfile is created after the first bootstrapping so that the full bootstrap process is only run once per server.

## Running Chef-Solo
You can run chef-solo for a single server by using:

```shell
cap server-<server name> cook
```

Or a all the servers with a given role with:

```shell
cap <role name> cook
```

Or on all servers:

```shell
cap all cook
```

## Updating Roles
If you change the roles of any servers on AWS (or add any new ones) you will need to run:

```shell
cap update_roles
```

This will update the *servers* data_bag as well as the capistrano stages.

## Additional Configuration
If you want to use a different tag name (or you like commas as a delimiter) you can specify your own role extractor/setter by placing the following in either your Capfile or config/deploy.rb:

```ruby
# these are the default - replace with your own
Toquen.config.aws_roles_extractor = lambda { |inst| (inst.tags["MyRoles"] || "").split(",") }
Toquen.config.aws_roles_setter = lambda { |ec2, inst, roles| ec2.tags.create(inst, 'Roles', :value => roles.sort.join(' ')) }
```

By default, instance information is only pulled out of the default region (us-east-1), but you can specify mutiple alternative regions:

```ruby
set :aws_regions, ['us-west-1', 'us-west-2']
```

You can also specify the location to upload the kitchen before running chef.  By default, this is set to the ssh user's home directory.

```ruby
set :chef_upload_location, "/tmp/toquen"
```

## View Instances
To see details about your aws instances you can use the **details** cap task.

```shell
cap all details
```

Or for a given role with:

```shell
cap <role name> details
```

Or for a given server with:

```shell
cap server-<server name> details
```

## Open SSH to Current Machine
To allow an SSH connection from your current machine (based on your internet visible IP, as determined using [this method](http://findingscience.com/internet/ruby/2014/05/17/stunning:-determining-your-public-ip.html)), use the open_ssh/close_ssh capistrano tasks.

```shell
cap databases open_ssh
```

And then, when you're finished:

```shell
cap databases close_ssh
```

Or, if you want to do everything in one step:

```shell
cap databases open_ssh cook close_ssh
```

**Note**: You can also use the task *open_port[22]* and *close_port[22]* to open and close SSH (or any other port).

## Application Configuration
Toquen can also drop off a config file meant for use by applications on your system.  Here's how that works:

1. Toquen creates a hash that contains a list of all of your servers and all of their details (based on your servers data_bag)
1. Toquen looks for a file named "apps.json" in your config folder, and if it's found, Toquen pulls out all of the keys that correspond with the server's roles and merges them together with the hash it's building (if this file contains secrets, consider *not* including in revision control)
1. The resulting hash is dropped off in your user's home directory (this can be overridden with the apps_config_path config variable) with the filename "apps.json".

This happens on every cook, and can be run separately as:

```shell
cap <role name> update_appconfig
```


## Additional Cap Tasks
There are a few other helper cap tasks as well - to see them, run:

```shell
cap -T
```