# frozen_string_literal: true

require_relative '../lib/rubyspeed'
require 'benchmark'

module BenchTestModule
  extend(Rubyspeed::Compiles)

  compile!
  def self.add_two_method(x)
    x * 5 + 2
  end

  def self.add_two_method_ruby(x)
    x * 5 + 2
  end
end

if BenchTestModule.add_two_method(100) != BenchTestModule.add_two_method_ruby(100)
  puts "Wrong code"
end

Benchmark.bmbm(7) do |x|
  x.report("compiled") { BenchTestModule.add_two_method(100) }
  x.report("ruby") { BenchTestModule.add_two_method_ruby(100) }
end
