require 'capistrano/setup'
require 'capistrano/console'
require 'set'
require 'json'

set :chef_upload_location, -> { "/home/#{fetch(:ssh_options)[:user]}" }

desc "update local cache of servers and roles"
task :update_roles do
  load Pathname.new fetch(:deploy_config_path, 'config/deploy.rb')
  roles = Hash.new([])
  servers = []

  aws = Toquen::AWSProxy.new
  aws.server_details.each do |details|
    details[:roles].each { |role| roles[role] += [details] }
    roles['all'] += [details]
    Toquen::LocalWriter.create_databag_item details
    Toquen::LocalWriter.create_stage "server-#{details[:name]}", [details]
    servers << details[:name]
  end

  roles.each { |name, servers| Toquen::LocalWriter.create_stage name, servers }

  # Look for any superfluous servers / roles
  Toquen::LocalWriter.superfluous_check!(servers, roles.keys)
end

desc "SSH into a specific server"
task :ssh do
  hosts = []
  on roles(:all) do |host|
    run_locally { hosts << host.hostname }
  end

  run_locally do
    if hosts.length == 0
      warn "No server matched that role"
    elsif hosts.length > 1
      warn "More than one server matched that role"
    else
      keys = fetch(:ssh_options)[:keys]
      keyoptions = keys.map { |key| "-i #{key}" }.join(' ')
      cmd = "ssh #{keyoptions} #{fetch(:ssh_options)[:user]}@#{hosts.first}"
      info "Running #{cmd}"
      exec cmd
    end
  end
end

desc "send up apps.json config file"
task :update_appconfig do
  return unless File.exists?('config/apps.json')
  apps = JSON.parse(File.read('config/apps.json'))
  config = { "_description" => "Dropped off by Toquen/Chef.", "servers" => [] }.merge(apps['default'] || {})
  Dir.glob("#{fetch(:chef_data_bags_path)}/servers/*.json") do |fname|
    open(fname, 'r') { |f| config['servers'] << JSON.parse(f.read) }
  end
  dest = File.join fetch(:apps_config_path, "/home/#{fetch(:ssh_options)[:user]}"), "apps.json"

  on roles(:all), in: :parallel do |host|
    appconfig = Marshal.load(Marshal.dump(config))
    host.properties.roles.each do |role|
      appconfig.merge!(apps[role.to_s] || {})
    end
    debug "Uploading app config file to #{dest}"
    upload! StringIO.new(JSON.pretty_generate(appconfig)), "/tmp/apps.json"
    sudo "mv /tmp/apps.json #{dest}"
    sudo "chmod 755 #{dest}"
  end
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
  kitchen = "#{fetch(:chef_upload_location)}/kitchen"
  lkitchen = "/tmp/toquen/kitchen"
  user = fetch(:ssh_options)[:user]
  keys = fetch(:ssh_options)[:keys]

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
    f.write("ssl_verify_mode :verify_peer\n")
  }

  on roles(:all), in: :parallel do |host|
    run_locally do
      info "Sending kitchen to #{host}..."
      keyoptions = keys.map { |key| "-i #{key}" }.join(' ')
      execute "rsync -avzk --delete -e 'ssh #{keyoptions}' #{lkitchen} #{user}@#{host}:#{fetch(:chef_upload_location)}"
    end
  end
end

desc "Run chef for servers"
task :cook do
  on roles(:all), in: :parallel do |host|
    info "Chef is now cooking on #{host}..."
    roles = host.properties.roles.reject { |r| r.to_s.start_with?('server-') or r == :all }
    roles = roles.map { |r| "\"role[#{r}]\"" }.join(',')
    info "Roles for #{host}: #{roles}"
    tfile = "chef.json"
    upload! StringIO.new("{ \"run_list\": [ #{roles} ] }"), tfile
    within fetch(:chef_upload_location) do
      execute "sudo chef-solo -c #{fetch(:chef_upload_location)}/kitchen/chef_config.rb -j #{tfile}"
    end
  end
end
before :cook, :update_kitchen

desc "Add given role to machines"
task :add_role, :role do |t, args|
  run_locally do
    if args[:role].nil? or args[:role].empty?
      error "You must give the role to add"
    else
      aws = Toquen::AWSProxy.new
      aws.add_role roles(:all), args[:role]
    end
  end
end

desc "Remove given role from machines"
task :remove_role, :role do |t, args|
  run_locally do
    if args[:role].nil? or args[:role].empty?
      error "You must give the role to remove"
    else
      aws = Toquen::AWSProxy.new
      aws.remove_role roles(:all), args[:role]
    end
  end
end

desc "Open a port of ingress to the current machine"
task :open_port, :port do |t, args|
  port = (args[:port] || 22).to_i
  run_locally do
    ivip = StunClient.get_ip
    if ivip.nil?
      error "Could not fetch internet visible IP of this host."
      return
    end

    ivip = "#{ivip}/32"
    aws = Toquen::AWSProxy.new
    aws.get_security_groups(fetch(:filter)[:secgroups]).each do |sg|
      if aws.authorize_ingress sg, :tcp, port, ivip
        info "Opened port tcp:#{port} on security group '#{sg.name}' (#{sg.id}) to #{ivip}"
      else
        warn "Port tcp:#{port} in security group '#{sg.name}' (#{sg.id}) already open to #{ivip}"
      end
    end
  end
end

desc "Close a port of ingress to the current machine"
task :close_port, :port do |t, args|
  port = (args[:port] || 22).to_i
  run_locally do
    ivip = StunClient.get_ip
    if ivip.nil?
      error "Could not fetch internet visible IP of this host."
      return
    end

    ivip = "#{ivip}/32"
    aws = Toquen::AWSProxy.new
    aws.get_security_groups(fetch(:filter)[:secgroups]).each do |sg|
      if aws.revoke_ingress sg, :tcp, port, ivip
        info "Closed port tcp:#{port} on security group '#{sg.name}' (#{sg.id}) to #{ivip}"
      else
        warn "Port tcp:#{port} in security group '#{sg.name}' (#{sg.id}) already closed to #{ivip}"
      end
    end
  end
end

desc "Open SSH ingress to current machine"
task :open_ssh do
  invoke "open_port", "22"
end

desc "Close SSH ingress to current machine"
task :close_ssh do
  invoke "close_port", "22"
end

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

desc "Show all information about EC2 instances"
task :details do
  filter_roles = Set.new fetch(:filter)[:roles]
  aws = Toquen::AWSProxy.new
  aws.regions.each do |region|
    instances = aws.server_details_in(region).reject do |instance|
      instance_roles = instance[:roles] + ["all", "server-#{instance[:name]}"]
      (filter_roles.intersection instance_roles.to_set).empty?
    end
    Toquen::DetailsTable.new(instances, region).output unless instances.empty?
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
