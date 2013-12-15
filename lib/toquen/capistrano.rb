require 'capistrano/setup'
require 'capistrano/console'

desc "update local cache of servers and roles"
task :update_roles do
  roles = Hash.new([])

  aws = Toquen::AWSProxy.new fetch(:aws_access_key_id), fetch(:aws_secret_access_key)
  aws.server_details.each do |details|
    open("#{fetch(:chef_data_bags_path)}/servers/#{details[:name]}.json", 'w') { |f|
      f.write JSON.dump(details)
    }
    details[:roles].each { |role| roles[role] += [details[:external_ip]] }
    roles['all'] += [details[:external_ip]]

    open("config/deploy/server-#{details[:name]}.rb", 'w') { |f|
      f.write("# This file will be overwritten by toquen!  Don't put anything here.\n")
      f.write("set :stage, 'server-#{details[:name]}'.intern\n")
      (details[:roles] + ["server-#{details[:name]}"]).each { |role|
        f.write("role '#{role}'.intern, %w{#{details[:external_ip]}}\n")  
      }
      f.write("set :filter, :roles => %w{server-#{details[:name]}}\n")
    }
  end
  
  roles.keys.each do |name|
    open("config/deploy/#{name}.rb", 'w') { |f|
      f.write("# This file will be overwritten by toquen!  Don't put anything here.\n")
      f.write("set :stage, '#{name}'.intern\n")
      roles.each { |n,ips|
        f.write("role '#{n}'.intern, %w{#{ips.reject(&:nil?).join(' ')}}\n")
      }
      f.write("set :filter, :roles => %w{#{name}}\n")
    }
  end
end

desc "bootstrap a server so that it can run chef"
task :bootstrap do
  rgems = "rubygems-#{fetch(:rubygems_version)}"
  on roles(:all), in: :parallel do |host|
    code = <<-EOF
#!/bin/bash
if [ -e "/home/#{fetch(:ssh_options)[:user]}/bootstrap.lock" ]; then exit 0; fi
DEBIAN_FRONTEND=noninteractive apt-get -y update
DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install ruby1.9.3 ruby-dev automake make
update-alternatives --set ruby /usr/bin/ruby1.9.1
cd /usr/src
rm -rf rubygems*
wget -q http://production.cf.rubygems.org/rubygems/#{rgems}.tgz
tar -zxf #{rgems}.tgz
cd /usr/src/#{rgems}
ruby setup.rb
gem install --no-rdoc --no-ri chef bundler
touch /home/#{fetch(:ssh_options)[:user]}/bootstrap.lock
reboot
EOF
    fname = "/home/#{fetch(:ssh_options)[:user]}/bootstrap.sh"
    upload! StringIO.new(code), fname
    sudo "sh #{fname}"
  end
end

desc "Update cookbooks/data bags/roles on server"
task :update_kitchen do
  kitchen = "/home/#{fetch(:ssh_options)[:user]}/kitchen"
  lkitchen = "/tmp/toquen/kitchen"
  user = fetch(:ssh_options)[:user]
  key = fetch(:ssh_options)[:keys].first

  run_locally do
    execute [
             "rm -rf #{lkitchen}", 
             "mkdir -p #{lkitchen}",
             "ln -s #{File.expand_path(fetch(:chef_cookbooks_path))} #{lkitchen}",
             "ln -s #{File.expand_path(fetch(:chef_data_bags_path))} #{lkitchen}",
             "ln -s #{File.expand_path(fetch(:chef_roles_path))} #{lkitchen}"
            ].join(" && ")
  end

  open("#{lkitchen}/chef_config.rb", 'w') { |f|
    f.write("file_cache_path '/var/chef-solo'\n")
    f.write("cookbook_path '#{kitchen}/cookbooks'\n")
    f.write("data_bag_path '#{kitchen}/data_bags'\n")
    f.write("role_path '#{kitchen}/roles'\n")
  }

  on roles(:all), in: :parallel do |host|
    run_locally do
      execute "rsync -avzk --delete -e 'ssh -i #{key}' #{lkitchen} #{user}@#{host}:/home/#{fetch(:ssh_options)[:user]}"
    end
  end
end

desc "Run chef for servers"
task :cook do
  on roles(:all), in: :parallel do |host|
    roles = host.properties.roles.reject { |r| r.to_s.start_with?('server-') }
    roles = roles.map { |r| "\"role[#{r}]\"" }.join(',')
    info "Roles for #{host}: #{roles}"
    tfile = "/home/#{fetch(:ssh_options)[:user]}/chef.json"
    upload! StringIO.new("{ \"run_list\": [ #{roles} ] }"), tfile
    execute "sudo chef-solo -c kitchen/chef_config.rb -j #{tfile}"
  end
end
before :cook, :update_kitchen

namespace :toquen do
desc "install toquen capistrano setup to current directory"
task :install do
    unless Dir.exists?('config')
      puts "Creating config directory..."
      Dir.mkdir('config')
    end
    unless Dir.exists?('config/deploy')
      puts "Creating config/deploy directory..."
      Dir.mkdir('config/deploy')
    end
    if not File.exists?('config/deploy.rb')
      puts "Initializing config/deploy.rb configuration file..."
      FileUtils.cp File.expand_path("../templates/deploy.rb", __FILE__), 'config/deploy.rb'
    end
  end
end
  
module Capistrano
  module TaskEnhancements
    alias_method :original_default_tasks, :default_tasks
    def default_tasks
      original_default_tasks + %w{toquen:install update_roles}
    end
  end
end
