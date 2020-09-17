# frozen_string_literal: true

require_relative '../lib/rubyspeed'
require 'benchmark'

module BenchTestModule
  extend(Rubyspeed::Compiles)

  compile!(params: [Rubyspeed::T.array(Rubyspeed::T.int), Rubyspeed::T.array(Rubyspeed::T.int)])
  def self.dot(a, b)
    c = Rubyspeed::Let.int(0)
    a.each_with_index do |a_val, idx|
      c += a_val * b[idx]
    end
    c
  end

  def self.dot_rb(a, b)
    c = Rubyspeed::Let.int(0)
    a.each_with_index do |a_val, idx|
      c += a_val * b[idx]
    end
    c
  end
end

INPUT_A = (3000..4000).to_a
INPUT_B = (4000..5000).to_a

if BenchTestModule.dot(INPUT_A, INPUT_B) != BenchTestModule.dot_rb(INPUT_A, INPUT_B)
  puts "Wrong code"
end

Benchmark.bmbm(7) do |x|
  x.report("compiled") { BenchTestModule.dot(INPUT_A, INPUT_B) }
  x.report("ruby") { BenchTestModule.dot_rb(INPUT_A, INPUT_B) }
end
