require 'erb'

module Toquen
  module Bootstrapper
    def self.generate_script(host)
      # host is available via the binding
      hosttype = fetch(:hosttype, 'ubuntu')
      path = File.expand_path("../templates/#{hosttype}_bootstrap.erb", __FILE__)
      raise "Bootstrap process for #{hosttype} does not exist!" unless File.exist?(path)
      user = fetch(:ssh_options)[:user]
      StringIO.new ERB.new(File.read(path)).result(binding)
    end
  end
end
