# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'toquen/version'

Gem::Specification.new do |gem|
  gem.name          = 'toquen'
  gem.version       = Toquen::VERSION
  gem.authors       = ['Brian Muller']
  gem.email         = ['bamuller@gmail.com']
  gem.description   = 'Toquen: Capistrano + AWS + Chef-Solo'
  gem.summary       = 'Toquen: Joins Capistrano + AWS + Chef-Solo into small devops ease'
  gem.homepage      = 'https://github.com/bmuller/toquen'
  gem.licenses      = ['MIT']

  gem.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']
  gem.add_dependency('capistrano', '~> 3.0', '>= 3.0.1')
  gem.add_dependency('aws-sdk', '~> 2')
  gem.add_dependency('terminal-table', '~> 1.6')
  gem.add_dependency('term-ansicolor', '~> 1.3')
  gem.add_development_dependency('rdoc', '~> 4.2')
  gem.add_development_dependency('rubocop')
end
