        #include "ruby.h"

        static VALUE example_branch(const VALUE self, const VALUE _flag, const VALUE _x) {
          int flag = FIX2INT(_flag);
int x = FIX2INT(_x);
          if ((flag) > (10)) { return INT2FIX(x);  }else if ((flag) > (5)) { return INT2FIX((x) + (1));  }else { return INT2FIX(0);  };
        }

        #ifdef __cplusplus
        extern "C" {
        #endif
        
        void Init_Rubyspeedi_6b22404fad5c81ace6a9ef111ef8c7ce() {
            const VALUE c = rb_path2class("Rubyspeed::CompileTarget");
            rb_define_singleton_method(c, "Rubyspeedi_6b22404fad5c81ace6a9ef111ef8c7ce_example_branch", (VALUE(*)(ANYARGS))example_branch, 2);
        }
        #ifdef __cplusplus
        }
        #endif
