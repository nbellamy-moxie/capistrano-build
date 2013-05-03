# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "capistrano-build"
  gem.homepage = "http://github.com/sammarx/capistrano-build"
  gem.license = "MIT"
  gem.summary = %Q{capistrano package and build tasks}
  gem.description = %Q{This gem will build and package artifacts, and push to an S3 repo}
  gem.email = "smarx@moxiesoft.com"
  gem.authors = ["Sam Marx"]
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new


task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "capistrano-build #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
