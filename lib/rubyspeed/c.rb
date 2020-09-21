module Rubyspeed
  module Internal
    module C
      class Context
        attr_reader :type_map, :return_type
        
        def initialize(type_map, return_type)
          @typemap = type_map
          @return_type = return_type
          @mangler = 0
        end

        def fresh_name(debug_name)
          name = "rbspeed_#{debug_name}_#{@mangler}"
          @mangler += 1
          name
        end
      end

      private_class_method def self.expr_seq(sexps, should_return:, ctx:)
        *exprs, last_expr = sexps

        out = exprs.map { |x| generate_c_expr(x, should_return: false, ctx: ctx) }.join(';')
        if exprs.length > 0
          out += ";"
        end
        out += "#{generate_c_expr(last_expr, should_return: should_return, ctx: ctx)};"

        out
      end

      private_class_method def self.get_method_call(val)
        raise "Expected :call, got #{val[0]}" if val[0] != :call

        # TODO we should find a better DSL for pattern matching this stuff
        # [:call, [:var_ref, [:@ident, "arr", [4, 4]]], [:@period, ".", [4, 7]], [:@ident, "each", [4, 8]]]
        raise "Expected :val_ref, got #{val[1][0]}" if val[1][0] != :var_ref
        raise "Expected :period, got #{val[2][0]}" if val[2][0] != :@period
        raise "Expected :ident, got #{val[3][0]}" if val[3][0] != :@ident

        [val[1][1][1], val[3][1]]
      end

      private_class_method def self.handle_return(val, should_return:, ctx:)
        if !should_return
          return val
        end

        return_type = ctx.return_type
        if return_type == 'VALUE'
          "return (#{val})"
        elsif return_type == 'void'
          "(#{val}); return Qnil"
        else
          "return #{FROM_C[return_type]}(#{val})"
        end
      end

      private_class_method def self.generate_c_expr(sexp, should_return:, ctx:)
        type = sexp[0]

        if type == :binary
          left = generate_c_expr(sexp[1], should_return: false, ctx: ctx)
          op = sexp[2]
          right = generate_c_expr(sexp[3], should_return: false, ctx: ctx)

          handle_return("(#{left}) #{op} (#{right})", should_return: should_return, ctx: ctx)
        elsif type == :@int
          handle_return("#{sexp[1]}", should_return: should_return, ctx: ctx)
        elsif type == :@ident || type == :@const
          handle_return("#{sexp[1]}", should_return: should_return, ctx: ctx)
        elsif type == :arg_paren
          handle_return("(#{generate_c_expr(sexp[1], should_return: false, ctx: ctx)})", should_return: should_return, ctx: ctx)
        elsif type == :args_add_block
          # TODO: this assumes single expr
          handle_return("(#{generate_c_expr(sexp[1][0], should_return: false, ctx: ctx)})", should_return: should_return, ctx: ctx)
        elsif type == :@op
          if sexp[1] == "+=" || sexp[1] == "-="
            sexp[1]
          else
            raise "Unknown operator #{sexp[1]}"
          end
        elsif type == :var_ref || type == :var_field
          generate_c_expr(sexp[1], should_return: should_return, ctx: ctx)
        elsif type == :aref
          var = generate_c_expr(sexp[1], should_return: false, ctx: ctx)
          ref = generate_c_expr(sexp[2], should_return: false, ctx: ctx)
          # TODO: is this correct? this only works for arrays
          # TODO: we assume the value is an int
          handle_return("FIX2INT(rb_ary_entry(#{var}, #{ref}))", should_return: should_return, ctx: ctx)
        elsif type == :opassign
          lhs = generate_c_expr(sexp[1], should_return: false, ctx: ctx)
          op = generate_c_expr(sexp[2], should_return: false, ctx: ctx)
          rhs = generate_c_expr(sexp[3], should_return: false, ctx: ctx)
          ret_helper = should_return ? "; return #{lhs}" : ""
          "#{lhs} #{op} (#{rhs})#{ret_helper}"
        elsif type == :const_path_ref
          pieces = sexp.drop(1).map do |el|
            generate_c_expr(el, should_return: false, ctx: ctx)
          end
          handle_return("#{pieces.join("_")}", should_return: should_return, ctx: ctx)
        elsif type == :@period
          "->" # TODO
        elsif type == :assign
          lhs = generate_c_expr(sexp[1], should_return: false, ctx: ctx)
          rhs = sexp[2]
          raise "Unexpected handler #{rhs[0]}" if rhs[0] != :method_add_arg
          call = rhs[1]
          raise "Unexpected call #{call[0]}" if call[0] != :call
          call_target = call.drop(1).map do |c|
            generate_c_expr(c, should_return: false, ctx: ctx)
          end.join('')
          lhs_ty =
            if call_target == "Rubyspeed_Let->int"
              "int"
            else
              raise "Unknown #{call_target} call target"
            end
          rhs_value = generate_c_expr(rhs[2], should_return: false, ctx: ctx)
          ret_helper = should_return ? ";#{handle_return(lhs, should_return: true, ctx: ctx)}" : ""
          "#{lhs_ty} #{lhs} = (#{rhs_value})#{ret_helper}"
        elsif type == :if || type == :elsif
          condition = generate_c_expr(sexp[1], should_return: false, ctx: ctx)
          body = expr_seq(sexp[2], should_return: should_return, ctx: ctx)
          rest = sexp[3] ? generate_c_expr(sexp[3], should_return: should_return, ctx: ctx) : ""
          ty = type == :if ? "if" : "else if"
          "#{ty} (#{condition}) { #{body}  }#{rest}"
        elsif type == :else
          body = expr_seq(sexp[1], should_return: should_return, ctx: ctx)
          "else { #{body}  }"
        elsif type == :method_add_block
          tgt, method = get_method_call(sexp[1])
          raise "Unknown method #{method}" if method != "each" && method != "each_with_index"
          has_index = method == "each_with_index"
          do_block = sexp[2]
          raise "Expecting do block" if do_block[0] != :do_block

          # TODO this hack hard-codes a single variable
          block_var = do_block[1]
          raise "Expecting block_var" if block_var[0] != :block_var
          param_name = block_var[1][1][0][1]
          if has_index
            index_name = block_var[1][1][1][1]
          end

          body = do_block[2]
          raise "Expected body" if body[0] != :bodystmt
          body_expr = expr_seq(body[1], should_return: false, ctx: ctx)

          ivar = ctx.fresh_name('i')
          lenvar = ctx.fresh_name('len')
          # TODO: this hard codes that the values of the parameter are ints
          out = ""
          out += "const long #{lenvar} = rb_array_len(#{tgt});"
          out += "for (int #{ivar} = 0; #{ivar} < #{lenvar}; #{ivar}++) {"
          if has_index
            out += "const int #{index_name} = #{ivar};";
          end
          out += "int #{param_name} = FIX2INT(rb_ary_entry(#{tgt}, #{ivar}));"
          out += body_expr
          out += "}"

          # TODO handle return
          out
        else
          print(sexp)
          raise "Unknown type #{type}"
        end
      end

      TO_C = {
        'int' => 'FIX2INT',
      }

      FROM_C = {
        'int' => 'INT2FIX',
      }

      private_class_method def self.boilerplate(module_name:, method_name:, args:, implementation:)
        # TODO: this should just add the method to an existing object/module
        is_windows = /mswin|mingw/ =~ RUBY_PLATFORM
        arg_conv = args.map do |a|
          if a[0] == 'VALUE'
            "VALUE #{a[1]} = _#{a[1]};"
          else
            "#{a[0]} #{a[1]} = #{TO_C[a[0]]}(_#{a[1]});"
          end
        end.join("\n")

        <<-EOF
        #include "ruby.h"

        static VALUE #{method_name}(const VALUE self, #{args.map { |a| "const VALUE _#{a[1]}"}.join(", ")}) {
          #{arg_conv}
          #{implementation}
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        #{is_windows ? "__declspec(dllexport)" : ""}
        void Init_#{module_name}() {
            const VALUE c = rb_path2class("Rubyspeed::CompileTarget");
            rb_define_singleton_method(c, "#{module_name}_#{method_name}", (VALUE(*)(ANYARGS))#{method_name}, #{args.length});
        }
        #ifdef __cplusplus
        }
        #endif
        EOF
      end

      def self.generate_c(sexp, arg_types:, return_type:)
        # TODO: this is likely better written with a library like oggy/cast
        out = ''
        raise "Must start at :program node" if sexp[0] != :program
        toplevel = sexp[1]
        raise "Must only contain single top level definition" if toplevel.length != 1 || (toplevel[0][0] != :def && toplevel[0][0] != :defs)
        # singleton = toplevel[0][0] == :defs
        definition = toplevel[0].drop(1)

        method_name = nil
        args = []
        out = ""
        context = Context.new({}, return_type)

        # TODO: this whole thing doesn't really assume a generic ast block, very hard-coded atm
        definition.each do |piece|
          type = piece[0]
          val = piece[1]

          if type == :@ident
            method_name = val
          end

          if type == :paren
            val[1].each_with_index do |param, i|
              ty = arg_types[i]
              args.push([ty, generate_c_expr(param, should_return: false, ctx: context)])
            end
          end

          if type == :bodystmt
            out += expr_seq(val, should_return: true, ctx: context)
          end
        end

        md5 = Digest::MD5.new
        md5 << method_name
        md5 << out
        module_name = "Rubyspeedi_#{md5}"

        [boilerplate(module_name: module_name, method_name: method_name, args: args, implementation: out), module_name]
      end
    end
  end
end
