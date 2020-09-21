# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../lib/rubyspeed'

class RubyspeedTestC < Minitest::Test
  TESTS = []

  def example_add(x)
    x + 1
  end
  TESTS.push(name: :example_add, args: [1], arg_types: [Rubyspeed::T.int], return_type: Rubyspeed::T.int)

  def example_branch(flag, x)
    if flag > 10
      x
    elsif flag > 5
      x + 1
    else
      0
    end
  end
  TESTS.push({name: :example_branch, args: [10, 10], arg_types: [Rubyspeed::T.int, Rubyspeed::T.int], return_type: Rubyspeed::T.int})

  def example_loop(arr)
    sum = Rubyspeed::Let.int(0)
    arr.each do |el|
      sum += el
    end
    sum
  end
  TESTS.push({name: :example_loop, args: [[1, 2]], arg_types: [Rubyspeed::T::array(Rubyspeed::T.int)], return_type: Rubyspeed::T.int})

  def example_dot(a, b)
    c = Rubyspeed::Let.int(0)
    a.each_with_index do |a_val, idx|
      c += a_val * b[idx]
    end
    c
  end
  TESTS.push({name: :example_dot, args: [[1, 2], [3, 4]], arg_types: [Rubyspeed::T::array(Rubyspeed::T.int), Rubyspeed::T::array(Rubyspeed::T.int)], return_type: Rubyspeed::T.int})

  TESTS.each do |test|
    define_method "test_#{test[:name]}" do
      src = Rubyspeed::Internal.retrieve_source(method(test[:name]))
      ast = Rubyspeed::Internal.parse_ast(src)
      c, module_name = Rubyspeed::Internal::C.generate_c(ast, arg_types: test[:arg_types], return_type: test[:return_type])

      file = File.join("fixtures", "#{test[:name]}.c")
      if File.file?(file)
        expected = File.read(file)
        assert_equal(expected, c)
      end

      compiled = Rubyspeed::Internal.compile_c(module_name, c)
      assert_equal(send(test[:name], *test[:args]), compiled.send("#{module_name}_#{test[:name]}", *test[:args]))

      if !File.file?(file)
        File.write(file, c, mode: "w")
      end
    end
  end
end
