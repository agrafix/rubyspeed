module Rubyspeed
  module Internal
    module C
      private_class_method def self.expr_seq(sexps, should_return:)
        *exprs, last_expr = sexps

        out = exprs.map { |x| generate_c_expr(x, should_return: false) }.join(';')
        out += "#{generate_c_expr(last_expr, should_return: should_return)};"
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

      private_class_method def self.generate_c_expr(sexp, should_return:)
        type = sexp[0]

        ret = should_return ? "return " : ""

        if type == :binary
          left = generate_c_expr(sexp[1], should_return: false)
          op = sexp[2]
          right = generate_c_expr(sexp[3], should_return: false)

          "#{ret}((#{left}) #{op} (#{right}))"
        elsif type == :@int
          "#{ret}#{sexp[1]}"
        elsif type == :@ident || type == :@const
          "#{ret}#{sexp[1]}"
        elsif type == :arg_paren
          "#{ret}(#{generate_c_expr(sexp[1], should_return: false)})"
        elsif type == :args_add_block
          # TODO: this assumes single expr
          "#{ret}(#{generate_c_expr(sexp[1][0], should_return: false)})"
        elsif type == :@op
          if sexp[1] == "+=" || sexp[1] == "-="
            sexp[1]
          else
            raise "Unknown operator #{sexp[1]}"
          end
        elsif type == :var_ref || type == :var_field
          generate_c_expr(sexp[1], should_return: should_return)
        elsif type == :opassign
          lhs = generate_c_expr(sexp[1], should_return: false)
          op = generate_c_expr(sexp[2], should_return: false)
          rhs = generate_c_expr(sexp[3], should_return: false)
          ret_helper = should_return ? "; return #{lhs}" : ""
          "#{lhs} #{op} (#{rhs})#{ret_helper}"
        elsif type == :const_path_ref
          pieces = sexp.drop(1).map do |el|
            generate_c_expr(el, should_return: false)
          end
          "#{ret}#{pieces.join("_")}"
        elsif type == :@period
          "->" # TODO
        elsif type == :assign
          lhs = generate_c_expr(sexp[1], should_return: false)
          rhs = sexp[2]
          raise "Unexpected handler #{rhs[0]}" if rhs[0] != :method_add_arg
          call = rhs[1]
          raise "Unexpected call #{call[0]}" if call[0] != :call
          call_target = call.drop(1).map do |c|
            generate_c_expr(c, should_return: false)
          end.join('')
          lhs_ty =
            if call_target == "Rubyspeed_T->int"
              "int"
            else
              raise "Unknown #{lhs_ty} type"
            end
          rhs_value = generate_c_expr(rhs[2], should_return: false)
          ret_helper = should_return ? "; return #{lhs}" : ""
          "#{lhs_ty} #{lhs} = (#{rhs_value})#{ret_helper}"
        elsif type == :if || type == :elsif
          condition = generate_c_expr(sexp[1], should_return: false)
          body = expr_seq(sexp[2], should_return: should_return)
          rest = sexp[3] ? generate_c_expr(sexp[3], should_return: should_return) : ""
          ty = type == :if ? "if" : "else if"
          "#{ty} (#{condition}) { #{body}  }#{rest}"
        elsif type == :else
          body = expr_seq(sexp[1], should_return: should_return)
          "else { #{body}  }"
        elsif type == :method_add_block
          tgt, method = get_method_call(sexp[1])
          raise "Unknown method #{method}" if method != "each"
          do_block = sexp[2]
          raise "Expecting do block" if do_block[0] != :do_block

          # TODO this hack hard-codes a single variable
          block_var = do_block[1]
          raise "Expecting block_var" if block_var[0] != :block_var
          param_name = block_var[1][1][0][1]

          body = do_block[2]
          raise "Expected body" if body[0] != :bodystmt
          body_expr = expr_seq(body[1], should_return: false)

          # TODO: mangle i due to nested loop
          # TODO: this hard codes that the values of the parameter are ints
          out = ""
          out += "long len = rb_array_len(#{tgt});"
          out += "for (int i = 0; i < len; i++) {"
          out += "int #{param_name} = FIX2INT(rb_ary_entry(#{tgt},i));"
          out += body_expr
          out += "}"

          # TODO handle return
          out
        else
          print(sexp)
          raise "Unknown type #{type}"
        end
      end

      def self.generate_c(sexp, arg_types: nil)
        # TODO: this is likely better written with a library like oggy/cast
        out = ''
        raise "Must start at :program node" if sexp[0] != :program
        toplevel = sexp[1]
        raise "Must only contain single top level definition" if toplevel.length != 1 || (toplevel[0][0] != :def && toplevel[0][0] != :defs)
        # singleton = toplevel[0][0] == :defs
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
            i = 0
            param_names = val[1].map do |param|
              # TODO: we need to know the parameter type
              ty =
                if arg_types
                  arg_types[i]
                else
                  "int"
                end
              i += 1
              "#{ty} #{generate_c_expr(param, should_return: false)}"
            end
            out += "(#{param_names.join(",")})"
          end

          if type == :bodystmt
            out += "{"
            out += expr_seq(val, should_return: true)
            out += "}"
          end
        end
        out
      end
    end
  end
end
