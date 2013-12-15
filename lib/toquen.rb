require "toquen/version"
require "toquen/aws"
require "toquen/capistrano"

module Toquen
  class Config
    attr_accessor :aws_roles_extractor

    def initialize
      Toquen.config.aws_roles_extractor = lambda { |inst| (inst.tags["Roles"] || "").split }
    end
  end

  def self.config
    @config ||= Config.new
  end
end
