        #include "ruby.h"

        static VALUE example_add(VALUE self, VALUE _x) {
          int x = FIX2INT(_x);
          return INT2FIX((x) + (1));
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_15cea6e71cc72a6aa056f820cd585cb3() {
            VALUE c = rb_define_class("Rubyspeedi_15cea6e71cc72a6aa056f820cd585cb3", rb_cObject);
            rb_define_method(c, "example_add", (VALUE(*)(ANYARGS))example_add, 1);
        }
        #ifdef __cplusplus
        }
        #endif
