require "toquen/version"
require "toquen/stunning"
require "toquen/aws"
require "toquen/local_writer"
require "toquen/bootstrapper"
require "toquen/capistrano"
require "toquen/details_table"

module Toquen
  class Config
    attr_accessor :aws_roles_extractor, :aws_roles_setter

    def initialize
      @aws_roles_extractor = lambda { |inst| (inst.tags["Roles"] || "").split }
      @aws_roles_setter = lambda { |ec2, inst, roles| ec2.tags.create(inst, 'Roles', :value => roles.sort.join(' ')) }
    end
  end

  def self.config
    @config ||= Config.new
  end
end
