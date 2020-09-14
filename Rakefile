require 'rubocop/rake_task'
require 'bundler/setup'
$:.unshift File.expand_path('../lib', __FILE__)

# rake console
task :console do
  require 'pry'
  require 'rubyspeed'
  ARGV.clear
  Pry.start
end

task default: %w[test lint]

task :test do
  ruby 'test/rubyspeed_test.rb'
end

RuboCop::RakeTask.new(:lint) do |task|
  task.patterns = ['lib/**/*.rb', 'test/**/*.rb']
  task.fail_on_error = false
end

task :typecheck do
  bundle exec srb tc
end
