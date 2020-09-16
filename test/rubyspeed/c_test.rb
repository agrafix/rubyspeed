# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/rubyspeed'

class RubyspeedTestC < Minitest::Test
  TESTS = []

  def example_add(x)
    x + 1
  end
  TESTS.push(name: :example_add, args: [1])

  def example_branch(flag, x)
    if flag > 10
      x
    elsif flag > 5
      x + 1
    else
      0
    end
  end
  TESTS.push({name: :example_branch, args: [10, 10]})

  TESTS.each do |test|
    define_method "test_#{test[:name]}" do
      src = Rubyspeed::Internal.retrieve_source(method(test[:name]))
      ast = Rubyspeed::Internal.parse_ast(src)
      c = Rubyspeed::Internal::C.generate_c(ast)

      file = File.join("fixtures", "#{test[:name]}.c")
      if !File.file?(file)
        File.write(file, c, mode: "w")
      else
        expected = File.read(file)
        assert_equal(expected, c)
      end

      compiled = Rubyspeed::Internal.compile_c("Compiled#{test[:name]}", c).new
      assert_equal(send(test[:name], *test[:args]), compiled.send(test[:name], *test[:args]))
    end
  end
end
