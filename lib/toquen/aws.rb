require 'aws'

module Toquen
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

    def get_security_groups(ids)
      ectwo = AWS::EC2.new
      ids.map { |id| ectwo.security_groups[id] }
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
      AWS::EC2.new.instances.map do |i|
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
