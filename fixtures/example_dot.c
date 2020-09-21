        #include "ruby.h"

        static VALUE example_dot(const VALUE self, const VALUE _a, const VALUE _b) {
          VALUE a = _a;
VALUE b = _b;
          int c = (((0)));const long rbspeed_len_1 = rb_array_len(a);for (int rbspeed_i_0 = 0; rbspeed_i_0 < rbspeed_len_1; rbspeed_i_0++) {const int idx = rbspeed_i_0;int a_val = FIX2INT(rb_ary_entry(a, rbspeed_i_0));c += ((a_val) * (FIX2INT(rb_ary_entry(b, (idx)))));};return INT2FIX(c);
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_ba928448ab77333865e42400b341073d() {
            const VALUE c = rb_path2class("Rubyspeed::CompileTarget");
            rb_define_singleton_method(c, "Rubyspeedi_ba928448ab77333865e42400b341073d_example_dot", (VALUE(*)(ANYARGS))example_dot, 2);
        }
        #ifdef __cplusplus
        }
        #endif
