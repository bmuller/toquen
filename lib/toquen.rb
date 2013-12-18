require "toquen/version"
require "toquen/aws"
require "toquen/local_writer"
require "toquen/bootstrapper"
require "toquen/capistrano"
require "toquen/details_table"

module Toquen
  class Config
    attr_accessor :aws_roles_extractor

    def initialize
      @aws_roles_extractor = lambda { |inst| (inst.tags["Roles"] || "").split }
    end
  end

  def self.config
    @config ||= Config.new
  end
end
