# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rubyspeed'

class RubyspeedTest < Minitest::Test
  #
  # Internals tests
  #
  def add_two_method(x)
    2 + x
  end

  def test_retrieve_source
    src = Rubyspeed::Internal.retrieve_source(method(:add_two_method))
    assert_equal(
      "  def add_two_method(x)\n" +
      "    2 + x\n" +
      "  end\n" +
      "", src)
  end

  def test_parse_ast
    src = Rubyspeed::Internal.retrieve_source(method(:add_two_method))
    ast = Rubyspeed::Internal.parse_ast(src)
    assert_equal(
      [:program,
       [[:def,
         [:@ident, "add_two_method", [1, 6]],
         [:paren, [:params, [[:@ident, "x", [1, 21]]], nil, nil, nil, nil, nil, nil]],
         [:bodystmt, [[:binary, [:@int, "2", [2, 4]], :+, [:var_ref, [:@ident, "x", [2, 8]]]]], nil, nil, nil]
        ]
       ]
      ], ast)
  end

  def test_generate_c
    src = Rubyspeed::Internal.retrieve_source(method(:add_two_method))
    ast = Rubyspeed::Internal.parse_ast(src)
    c = Rubyspeed::Internal.generate_c(ast)
    assert_equal("int add_two_method(int x){return ((2) + (x));}", c)
  end

  def test_compile_c
    src = Rubyspeed::Internal.retrieve_source(method(:add_two_method))
    ast = Rubyspeed::Internal.parse_ast(src)
    c = Rubyspeed::Internal.generate_c(ast)
    compiled = Rubyspeed::Internal.compile_c("TestCompileC", c)
    result = compiled.new.add_two_method(5)
    assert_equal(7, result)
  end

  #
  # Public API tests
  #
  class TestClass
    extend(Rubyspeed::Compiles)

    compile!
    def add_two_method(x)
      x + 2
    end

    def add_two_method_ruby(x)
      x + 2
    end
  end

  def test_class_decorator
    c = TestClass.new
    assert_equal(c.add_two_method(2), c.add_two_method_ruby(2))
  end

  module TestModule
    extend(Rubyspeed::Compiles)

    compile!
    def self.add_two_method(x)
      x + 2
    end

    def self.add_two_method_ruby(x)
      x + 2
    end
  end

  def test_module_decorator
    assert_equal(TestModule.add_two_method(2), TestModule.add_two_method_ruby(2))
  end
end
