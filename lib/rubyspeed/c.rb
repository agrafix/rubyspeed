module Rubyspeed
  module Internal
    module C
      private_class_method def self.expr_seq(sexps, should_return:)
        *exprs, last_expr = sexps

        out = exprs.map { |x| generate_c_expr(x, should_return: false) }.join(';')
        out += "#{generate_c_expr(last_expr, should_return: should_return)};"
        out
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
        elsif type == :@ident
          "#{ret}#{sexp[1]}"
        elsif type == :var_ref
          generate_c_expr(sexp[1], should_return: should_return)
        elsif type == :if || type == :elsif
          condition = generate_c_expr(sexp[1], should_return: false)
          body = expr_seq(sexp[2], should_return: should_return)
          rest = sexp[3] ? generate_c_expr(sexp[3], should_return: should_return) : ""
          ty = type == :if ? "if" : "else if"
          "#{ty} (#{condition}) { #{body}  }#{rest}"
        elsif type == :else
          body = expr_seq(sexp[1], should_return: should_return)
          "else { #{body}  }"
        else
          print(sexp)
          raise "Unknown type #{type}"
        end
      end

      def self.generate_c(sexp)
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
            param_names = val[1].map do |param|
              # TODO: we need to know the parameter type
              "int #{generate_c_expr(param, should_return: false)}"
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
