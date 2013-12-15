require 'aws'

module Toquen
  class AWSProxy
    def initialize(key_id, key)
      AWS.config(:access_key_id => key_id, :secret_access_key => key)
    end

    def server_details
      AWS::EC2.new.instances.map do |i|
        {
          :id => i.tags["Name"],
          :internal_ip => i.private_ip_address,
          :external_ip => i.public_ip_address,
          :name => i.tags["Name"],
          :roles => Toquen.config.aws_roles_extractor.call(i)
        }
      end
    end
  end
end
