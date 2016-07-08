module Toquen
  module LocalWriter
    def self.create_node(details)
      FileUtils.mkdir_p fetch(:chef_nodes_path)
      path = File.join(fetch(:chef_nodes_path), "#{details[:name]}.json")
      existing = File.exists?(path) ? JSON.parse(File.read(path)) : {}
      open(path, 'w') do |f|
        node = {
          'name' => details[:name],
          'chef_environment' => details[:environment],
          'normal' => { toquen: details },
          'run_list' => details[:roles].map { |r| "role[#{r}]" }
        }
        f.write JSON.pretty_generate(existing.merge(node))
      end
    end

    def self.create_stage(name, servers)
      run_locally { info "Creating stage '#{name}' with servers: #{servers.map { |s| s[:name] }.join(', ')}" }
      open("config/deploy/#{name}.rb", 'w') do |f|
        f.write("# This file will be overwritten by toquen!  Don't put anything here.\n")
        f.write("set :stage, '#{name}'.intern\n")
        secgroups = []
        servers.each { |details|
          rstring = (details[:roles] + [ "all", "server-#{details[:name]}" ]).join(' ')
          f.write("server '#{details[:external_ip]}', ")
          f.write("roles: %w{#{rstring}}, ")
          f.write("environment: \"#{details[:environment]}\", ") unless details[:environment].nil?
          f.write("awsname: '#{details[:name]}'\n")
          secgroups += details[:security_groups]
        }
        secstring = secgroups.uniq.join(' ')
        f.write("set :filter, roles: %w{#{name}}, secgroups: %w{#{secstring}}\n")
      end
    end

    def self.superfluous_check!(servers, roles)
      # check for superflous stages / data bag items and warn if found
      run_locally do
        Dir["#{fetch(:chef_data_bags_path)}/servers/*.json"].each { |path|
          unless servers.include? File.basename(path, ".json")
            warn "Data bag item #{path} does not represent an active server. You should delete it."
          end
        }

        stages = roles + servers.map { |n| "server-#{n}" }
        Dir["config/deploy/*.rb"].each { |path|
          unless stages.include? File.basename(path, ".rb")
            warn "Stage #{path} does not represent an active server. You should delete it."
          end
        }
      end
    end
  end
end
