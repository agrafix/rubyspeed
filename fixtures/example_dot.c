int example_dot(VALUE a,VALUE b){int c = (((0)));long len = rb_array_len(a);for (int i = 0; i < len; i++) {int idx = i;int a_val = FIX2INT(rb_ary_entry(a,i));c += (((a_val) * (FIX2INT(rb_ary_entry(b, (idx))))));}return c;}