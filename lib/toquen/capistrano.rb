require 'capistrano/setup'
require 'capistrano/console'

desc "update local cache of servers and roles"
task :update_roles do
  load Pathname.new fetch(:deploy_config_path, 'config/deploy.rb')
  roles = Hash.new([])

  aws = Toquen::AWSProxy.new
  aws.server_details.each do |details|
    details[:roles].each { |role| roles[role] += [details] }
    roles['all'] += [details]
    Toquen::LocalWriter.create_databag_item details
    Toquen::LocalWriter.create_stage "server-#{details[:name]}", [details]
  end

  roles.each { |name, servers| Toquen::Writer.create_stage name, servers }
end

desc "bootstrap a server so that it can run chef"
task :bootstrap do
  on roles(:all), in: :parallel do |host|
    info "Bootstrapping #{host}..."
    fname = "/home/#{fetch(:ssh_options)[:user]}/bootstrap.sh"
    upload! Toquen::Bootstrapper.generate_script(host), fname
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
    info "Building kitchen locally..."
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
      info "Sending kitchen to #{host}..."
      execute "rsync -avzk --delete -e 'ssh -i #{key}' #{lkitchen} #{user}@#{host}:/home/#{fetch(:ssh_options)[:user]}"
    end
  end
end

desc "Run chef for servers"
task :cook do
  on roles(:all), in: :parallel do |host|
    info "Chef is now cooking on #{host}..."
    roles = host.properties.roles.reject { |r| r.to_s.start_with?('server-') }
    roles = roles.map { |r| "\"role[#{r}]\"" }.join(',')
    info "Roles for #{host}: #{roles}"
    tfile = "/home/#{fetch(:ssh_options)[:user]}/chef.json"
    upload! StringIO.new("{ \"run_list\": [ #{roles} ] }"), tfile
    execute "sudo chef-solo -c kitchen/chef_config.rb -j #{tfile}"
  end
end
before :cook, :update_kitchen

desc "install toquen capistrano setup to current directory"
task :toquen_install do
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
  
module Capistrano
  module TaskEnhancements
    alias_method :original_default_tasks, :default_tasks
    def default_tasks
      original_default_tasks + %w{toquen_install update_roles}
    end
  end
end
