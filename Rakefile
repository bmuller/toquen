require "bundler/gem_tasks"
require 'rdoc/task'

RDoc::Task.new("doc") { |rdoc|
  rdoc.title = "Capistrano + AWS + Chef-Solo"
  rdoc.rdoc_dir = 'docs'
  rdoc.rdoc_files.include('README.md')
  rdoc.rdoc_files.include('lib/**/*.rb')
}