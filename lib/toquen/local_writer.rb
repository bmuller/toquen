module Toquen
  module LocalWriter
    def self.create_databag_item(details)
      open("#{fetch(:chef_data_bags_path)}/servers/#{details[:name]}.json", 'w') do |f|
        f.write JSON.dump(details)
      end
    end

    def self.create_stage(name, servers)
      run_locally { info "Creating stage '#{name}' with servers: #{servers.map { |s| s[:name] }.join(', ')}" }
      open("config/deploy/#{name}.rb", 'w') do |f|
        f.write("# This file will be overwritten by toquen!  Don't put anything here.\n")
        f.write("set :stage, '#{name}'.intern\n")
        servers.each { |details|
          rstring = (details[:roles] + [ "all", "server-#{details[:name]}" ]).join(' ')
          f.write("server '#{details[:external_ip]}', roles: %w{#{rstring}}, awsname: '#{details[:name]}'\n")
        }
        f.write("set :filter, roles: %w{#{name}}\n")
      end
    end
  end
end
