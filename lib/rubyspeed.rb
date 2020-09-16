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

    def compile!
      Thread.current[:rubyspeed_should_compile] = true
    end
  end

  module Internal
    def self.handle_new_method(target, name, singleton:)
      target_name = target.name
      if !Thread.current[:rubyspeed_should_compile]
        return
      end
      Thread.current[:rubyspeed_should_compile] = false

      target = singleton ? target.singleton_class : target
      original_impl = target.instance_method(name)
      source = retrieve_source(original_impl)
      ast = parse_ast(source)
      c = C.generate_c(ast)

      md5 = Digest::MD5.new
      md5 << target_name
      md5 << source

      compiled = compile_c("Rubyspeed_#{md5.hexdigest}", c).new

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

    def self.compile_c(key, code)
      Inliner.inline(key) do |builder|
        builder.c(code)
      end
      Object.const_get(key)
    end
  end
end
