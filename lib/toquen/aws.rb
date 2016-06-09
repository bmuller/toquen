require 'aws'

module Toquen
  def self.servers_with_role(role)
    Toquen::AWSProxy.new.server_details.select do |details|
      details[:roles].include? role
    end
  end

  class AWSProxy
    attr_reader :regions

    def initialize
      @key_id = fetch(:aws_access_key_id)
      @key = fetch(:aws_secret_access_key)
      @regions = fetch(:aws_regions, ['us-east-1'])
      AWS.config(:access_key_id => @key_id, :secret_access_key => @key)
    end

    def server_details
      filter @regions.map { |region| server_details_in(region) }.flatten
    end

    def filter(details)
      details.select { |detail|
        not detail[:name].nil? and detail[:roles].length > 0
      }
    end

    def add_role(ivips, role)
      @regions.each do |region|
        AWS.config(:access_key_id => @key_id, :secret_access_key => @key, :region => region)
        ec2 = AWS::EC2.new
        ec2.instances.map do |i|
          if ivips.include? i.public_ip_address
            roles = Toquen.config.aws_roles_extractor.call(i)
            unless roles.include? role
              roles << role
              ec2.tags.create(i, 'Roles', :value => roles.uniq.sort.join(' '))
            end
          end
        end
      end
    end

    def remove_role(ivips, role)
      @regions.each do |region|
        AWS.config(:access_key_id => @key_id, :secret_access_key => @key, :region => region)
        ec2 = AWS::EC2.new
        ec2.instances.map do |i|
          if ivips.include? i.public_ip_address
            roles = Toquen.config.aws_roles_extractor.call(i)
            if roles.include? role
              roles = roles.reject { |r| r == role }
              Toquen.config.aws_roles_setter.call(ec2, i, roles.uniq)
            end
          end
        end
      end
    end

    def get_security_groups(ids)
      result = []
      @regions.map do |region|
        AWS.config(:access_key_id => @key_id, :secret_access_key => @key, :region => region)
        AWS.memoize do
          ectwo = AWS::EC2.new
          ectwo.security_groups.each { |sg| result << sg if ids.include? sg.id }
        end
      end
      result
    end

    def authorize_ingress(secgroup, protocol, port, ip)
      # test if exists first
      return false if secgroup.ingress_ip_permissions.to_a.select { |p|
        p.protocol == protocol and p.port_range.include?(port) and p.ip_ranges.include?(ip)
      }.length > 0

      secgroup.authorize_ingress(protocol, port, ip)
      true
    end

    def revoke_ingress(secgroup, protocol, port, ip)
      # test if exists first
      return false unless secgroup.ingress_ip_permissions.to_a.select { |p|
        p.protocol == protocol and p.port_range.include?(port) and p.ip_ranges.include?(ip)
      }.length > 0

      secgroup.revoke_ingress(protocol, port, ip)
      true
    end

    def server_details_in(region)
      AWS.config(:access_key_id => @key_id, :secret_access_key => @key, :region => region)
      AWS.memoize do
        AWS::EC2.new.instances.filter("instance-state-name", "running").map do |i|
          {
            :id => i.tags["Name"],
            :internal_ip => i.private_ip_address,
            :external_ip => i.public_ip_address,
            :name => i.tags["Name"],
            :roles => Toquen.config.aws_roles_extractor.call(i),
            :type => i.instance_type,
            :external_dns => i.public_dns_name,
            :internal_dns => i.private_dns_name,
            :security_groups => i.security_groups.to_a.map(&:id)
          }
        end
      end
    end

  end
end
