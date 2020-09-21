# frozen_string_literal: true

require 'method_source'
require 'ripper'
require 'digest'

require_relative './inline'
require_relative './rubyspeed/c'

module Rubyspeed
  VERSION = '0.0.1'

  module Compiles
    def method_added(name)
      super(name)
      Rubyspeed::Internal.handle_new_method(self, name, singleton: false)
    end

    def singleton_method_added(name)
      super(name)
      Rubyspeed::Internal.handle_new_method(self, name, singleton: true)
    end

    def compile!(params:, return_type:)
      Thread.current[:rubyspeed_should_compile] = {params: params, return_type: return_type}
    end
  end

  module T
    def self.array(of)
      "VALUE"
    end

    def self.int()
      "int"
    end
  end

  module Let
    def self.int(x)
      x
    end
  end

  class CompileTarget
    # TODO: all compiled methods to end up here
  end

  module Internal
    def self.handle_new_method(target, name, singleton:)
      if !Thread.current[:rubyspeed_should_compile]
        return
      end
      config = Thread.current[:rubyspeed_should_compile]
      Thread.current[:rubyspeed_should_compile] = nil

      target = singleton ? target.singleton_class : target
      original_impl = target.instance_method(name)
      source = retrieve_source(original_impl)
      ast = parse_ast(source)
      # TODO: return type should be configurable
      c, module_name = C.generate_c(ast, arg_types: config[:params], return_type: config[:return_type])

      compiled = compile_c(module_name, c)

      compiled_name = "#{module_name}_#{name}"
      # TODO: keep visibility etc.
      target.send(:define_method, name) do |*args, &blk|
        compiled.send(compiled_name, *args, &blk)
      end
    end

    def self.retrieve_source(method)
      method.source
    end

    def self.parse_ast(source)
      Ripper.sexp(source)
    end

    def self.compile_c(key, code)
      builder = Inline::C.new(key, code)
      if !builder.load_cache
        builder.build
        builder.load
      end
      CompileTarget
    end
  end
end
