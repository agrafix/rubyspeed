        #include "ruby.h"

        static VALUE example_add(const VALUE self, const VALUE _x) {
          int x = FIX2INT(_x);
          return INT2FIX((x) + (1));
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_15cea6e71cc72a6aa056f820cd585cb3() {
            const VALUE c = rb_path2class("Rubyspeed::CompileTarget");
            rb_define_singleton_method(c, "Rubyspeedi_15cea6e71cc72a6aa056f820cd585cb3_example_add", (VALUE(*)(ANYARGS))example_add, 1);
        }
        #ifdef __cplusplus
        }
        #endif
