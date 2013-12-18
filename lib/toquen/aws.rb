require 'aws'

module Toquen
  class AWSProxy
    attr_reader :regions

    def initialize
      @key_id = fetch(:aws_access_key_id)
      @key = fetch(:aws_secret_access_key)
      @regions = fetch(:aws_regions, ['us-east-1'])
    end

    def server_details
      filter @regions.map { |region| server_details_in(region) }.flatten
    end

    def filter(details)
      details.select { |detail|
        not detail[:name].nil? and detail[:roles].length > 0
      }
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
          :internal_dns => i.private_dns_name
        }
      end
    end

  end
end
