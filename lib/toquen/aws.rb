require 'aws-sdk'

# Top level module namespace
module Toquen
  def self.servers_with_role(role)
    Toquen::AWSProxy.new.server_details.select do |details|
      details[:roles].include? role
    end
  end

  # Class to handle all interaction with AWS
  class AWSProxy
    attr_reader :regions

    def initialize
      @regions = fetch(:aws_regions, ['us-east-1'])
      key = fetch(:aws_access_key_id)
      key_id = fetch(:aws_secret_access_key)
      creds = Aws::Credentials.new(key, key_id)
      Aws.config.update(credentials: creds) if creds.set?
    end

    def server_details(running = true, regions = nil)
      each_instance(running, regions) { |inst| extract_details(inst) }
    end

    def each_instance(running = true, regions = nil)
      filters = []
      filters << { name: 'instance-state-name', values: ['running'] } if running

      results = []
      (regions || @regions).each do |region|
        resource = Aws::EC2::Resource.new(region: region)
        results += resource.instances.map { |i| yield(i) }
      end
      results
    end

    def add_role(ivips, role)
      each_instance do |i|
        roles = extract_details(i)[:roles]
        next unless !roles.include?(role) && ivips.include?(i.public_ip_address)
        roles << role
        tag = { key: 'Roles', value: roles.uniq.sort.join(' ') }
        i.create_tags(tags: [tag])
      end
    end

    def remove_role(ivips, role)
      each_instance do |i|
        roles = extract_details(i)[:roles]
        next unless roles.include?(role) && ivips.include?(i.public_ip_address)
        roles.reject! { |r| r == role }
        tag = { key: 'Roles', value: roles.uniq.sort.join(' ') }
        i.create_tags(tags: [tag])
      end
    end

    def get_security_groups(ids)
      @regions.map do |region|
        sgs = Aws::EC2::Resource.new(region: region).security_groups
        sgs.select { |sg| ids.include? sg.group_id }
      end.flatten
    end

    def authorize_ingress(secgroup, protocol, port, ip)
      # test if exists first
      return false unless secgroup.ip_permissions.to_a.select do |p|
        port_match = ((p.from_port)..(p.to_port)).cover? port
        ip_match = p.ip_ranges.map(&:cidr_ip).include?(ip)
        p.ip_protocol == protocol && port_match && ip_match
      end.empty?

      secgroup.authorize_ingress(ip_protocol: protocol, from_port: port,
                                 to_port: port, cidr_ip: ip)
      true
    end

    def revoke_ingress(secgroup, protocol, port, ip)
      # test if exists first
      return false if secgroup.ip_permissions.to_a.select do |p|
        port_match = ((p.from_port)..(p.to_port)).cover? port
        ip_match = p.ip_ranges.map(&:cidr_ip).include?(ip)
        p.ip_protocol == protocol && port_match && ip_match
      end.empty?

      secgroup.revoke_ingress(ip_protocol: protocol, from_port: port,
                              to_port: port, cidr_ip: ip)
      true
    end

    def extract_details(instance)
      tags = instance.tags.each_with_object({}) { |t, h| h[t.key] = t.value }
      {
        id: tags['Name'],
        name: tags['Name'],
        type: instance.instance_type,
        environment: tags['Environment'],
        internal_ip: instance.private_ip_address,
        external_ip: instance.public_ip_address,
        external_dns: instance.public_dns_name,
        internal_dns: instance.private_dns_name,
        roles: tags.fetch('Roles', '').split,
        security_groups: instance.security_groups.map(&:group_id)
      }
    end
  end
end
