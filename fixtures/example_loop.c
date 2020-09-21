        #include "ruby.h"

        static VALUE example_loop(VALUE self, VALUE _arr) {
          VALUE arr = _arr;
          int sum = (((0)));long rbspeed_len_1 = rb_array_len(arr);for (int rbspeed_i_0 = 0; rbspeed_i_0 < rbspeed_len_1; rbspeed_i_0++) {int el = FIX2INT(rb_ary_entry(arr, rbspeed_i_0));sum += (el);};return INT2FIX(sum);
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_7f29d0f2adc9b571bf2f4adb4c13f278() {
            VALUE c = rb_define_class("Rubyspeedi_7f29d0f2adc9b571bf2f4adb4c13f278", rb_cObject);
            rb_define_method(c, "example_loop", (VALUE(*)(ANYARGS))example_loop, 1);
        }
        #ifdef __cplusplus
        }
        #endif
