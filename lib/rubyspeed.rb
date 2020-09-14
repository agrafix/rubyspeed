# frozen_string_literal: true

require 'method_source'
require 'ripper'
require 'digest'

require_relative './inline'

module Rubyspeed
  VERSION = '0.0.1'

  module Compiles
    def method_added(name)
      super(name)
      Rubyspeed::Internal.handle_new_method(self, name)
    end

    def compile!
      Thread.current[:rubyspeed_should_compile] = true
    end
  end

  module Internal
    def self.handle_new_method(target, name)
      if !Thread.current[:rubyspeed_should_compile]
        return
      end
      Thread.current[:rubyspeed_should_compile] = false

      original_impl = target.instance_method(name)
      source = retrieve_source(original_impl)
      ast = parse_ast(source)
      c = generate_c(ast)
      compiled = compile_c("Rubyspeed_#{Digest::MD5.hexdigest(source)}", c).new

      # TODO: keep visibility etc.
      target.send(:define_method, name) do |*args, &blk|
        compiled.send(name, *args, &blk)
      end
    end

    def self.retrieve_source(method)
      method.source
    end

    def self.parse_ast(source)
      Ripper.sexp(source)
    end

    private_class_method def self.generate_c_expr(sexp)
      type = sexp[0]

      if type == :binary
        left = generate_c_expr(sexp[1])
        op = sexp[2]
        right = generate_c_expr(sexp[3])

        "((#{left}) #{op} (#{right}))"
      elsif type == :@int
        "#{sexp[1]}"
      elsif type == :@ident
        "#{sexp[1]}"
      elsif type == :var_ref
        generate_c_expr(sexp[1])
      else
        raise "Unknown type #{type}"
      end
    end

    def self.generate_c(sexp)
      # TODO: this is likely better written with a library like oggy/cast
      out = ''
      raise "Must start at :program node" if sexp[0] != :program
      toplevel = sexp[1]
      raise "Must only contain single top level definition" if toplevel.length != 1 || toplevel[0][0] != :def
      definition = toplevel[0].drop(1)

      # TODO: this whole thing doesn't really assume a generic ast block, very hard-coded atm
      definition.each do |piece|
        type = piece[0]
        val = piece[1]

        if type == :@ident
          # TODO: we need to know the return time, type inference is needed.
          out += "int #{val}"
        end

        if type == :paren
          param_names = val[1].map do |param|
            # TODO: we need to know the parameter type
            "int #{generate_c_expr(param)}"
          end
          out += "(#{param_names.join(",")})"
        end

        if type == :bodystmt
          *exprs, last_expr = val

          out += "{"
          out += exprs.map { |x| generate_c_expr(x) }.join(';')
          out += "return #{generate_c_expr(last_expr)};"
          out += "}"
        end
      end

      out
    end

    def self.compile_c(key, code)
      Inliner.inline(key) do |builder|
        builder.c(code)
      end
      Object.const_get(key)
    end
  end
end
