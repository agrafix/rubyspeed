        #include "ruby.h"

        static VALUE example_dot(VALUE self, VALUE _a, VALUE _b) {
          VALUE a = _a;
VALUE b = _b;
          int c = (((0)));long rbspeed_len_1 = rb_array_len(a);for (int rbspeed_i_0 = 0; rbspeed_i_0 < rbspeed_len_1; rbspeed_i_0++) {int idx = rbspeed_i_0;int a_val = FIX2INT(rb_ary_entry(a, rbspeed_i_0));c += ((a_val) * (FIX2INT(rb_ary_entry(b, (idx)))));};return INT2FIX(c);
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_ab8791c09840ee6c163191a8692274a2() {
            VALUE c = rb_define_class("Rubyspeedi_ab8791c09840ee6c163191a8692274a2", rb_cObject);
            rb_define_method(c, "example_dot", (VALUE(*)(ANYARGS))example_dot, 2);
        }
        #ifdef __cplusplus
        }
        #endif
