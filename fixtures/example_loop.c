        #include "ruby.h"

        static VALUE example_loop(const VALUE self, const VALUE _arr) {
          VALUE arr = _arr;
          int sum = (((0)));const long rbspeed_len_1 = rb_array_len(arr);for (int rbspeed_i_0 = 0; rbspeed_i_0 < rbspeed_len_1; rbspeed_i_0++) {int el = FIX2INT(rb_ary_entry(arr, rbspeed_i_0));sum += (el);};return INT2FIX(sum);
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_8a9ee7a43846aada09e7132c19791461() {
            const VALUE c = rb_path2class("Rubyspeed::CompileTarget");
            rb_define_singleton_method(c, "Rubyspeedi_8a9ee7a43846aada09e7132c19791461_example_loop", (VALUE(*)(ANYARGS))example_loop, 1);
        }
        #ifdef __cplusplus
        }
        #endif
