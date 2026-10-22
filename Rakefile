# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "rdoc/task"

# Test task configuration
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

# RDoc task configuration
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'doc'
  rdoc.title    = 'CalInvite Documentation'
  rdoc.main     = 'README.md'

  # Configure RDoc options
  rdoc.options << '--line-numbers'
  rdoc.options << '--charset' << 'UTF-8'
  rdoc.options << '--markup' << 'markdown'
  rdoc.options << '--all'
  rdoc.options << '--exclude' << '^(test|spec|features)/'

  # Include files to document
  rdoc.rdoc_files.include('README.md', 'CONFIGURATION.md', 'CACHING.md', 'CHANGELOG.md',
                          'SECURITY.md', 'CODE_OF_CONDUCT.md', 'LICENSE.txt', 'lib/**/*.rb')
  rdoc.rdoc_files.exclude('lib/cal_invite/version.rb')
end

# Define a task to clean documentation
task 'rdoc:clean' do
  rm_rf 'doc'
end

# Keep test as the default task
task default: :test
