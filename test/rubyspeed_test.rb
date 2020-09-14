# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/rubyspeed'

class RubyspeedTest < Minitest::Test
  def add_two_method(x)
    2 + x
  end

  def test_retrieve_source
    src = Rubyspeed.retrieve_source(method(:add_two_method))
    assert_equal(
      "  def add_two_method(x)\n" +
      "    2 + x\n" +
      "  end\n" +
      "", src)
  end

  def test_parse_ast
    src = Rubyspeed.retrieve_source(method(:add_two_method))
    ast = Rubyspeed.parse_ast(src)
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
    src = Rubyspeed.retrieve_source(method(:add_two_method))
    ast = Rubyspeed.parse_ast(src)
    c = Rubyspeed.generate_c(ast)
    assert_equal("int add_two_method(int x){return ((2) + (x));}", c)
  end

  def test_compile_c
    src = Rubyspeed.retrieve_source(method(:add_two_method))
    ast = Rubyspeed.parse_ast(src)
    c = Rubyspeed.generate_c(ast)
    compiled = Rubyspeed.compile_c(c)
    result = compiled.new.add_two_method(5)
    assert_equal(7, result)
  end
end
