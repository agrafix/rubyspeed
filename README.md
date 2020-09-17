# Rubyspeed

_Work in progress._

Welcome to Rubyspeed. Right now, Rubyspeed is a very early proof of concept that allows annotating method declarations to automatically be compiled to C. Here's an example:

``` ruby
require 'rubyspeed'

class TestClass
  extend(Rubyspeed::Compiles)
    
  compile!(params: [Rubyspeed::T.array(Rubyspeed::T.int), Rubyspeed::T.array(Rubyspeed::T.int)])
  def self.dot(a, b)
    c = Rubyspeed::Let.int(0)
    a.each_with_index do |a_val, idx|
      c += a_val * b[idx]
    end
    c
  end
end
```

What this will do is replace the `dot` with a compiled C implementation, that runs quite a bit faster than the native ruby version:

```bash
$ rake bench
               user     system      total        real
compiled   0.000021   0.000004   0.000025 (  0.000018)
ruby       0.000105   0.000002   0.000107 (  0.000103)
```

## Who does this work?
_this section needs some work_

In short:

* Use a neat annotation trick inspired by the [sorbet runtime](https://github.com/sorbet/sorbet/blob/d4c80e0ac3b04e64770f1b050fbab3c6c39b58eb/gems/sorbet-runtime/lib/types/private/methods/_methods.rb#L461) to emulate annotations (compare to `@Deprecated` in Java for example)
* Extract the ruby source from the given method
* Transform it to s-expressions
* Generate C code from the s-expressions
* Use a C compile to compile to a ruby module
* Replace original implementation with a call to the compiled ruby module

## Inspiration

This project was inspired by [Stephen Diehl's LLVM specializer for Python](http://dev.stephendiehl.com/numpile/) and [rubyinline](https://github.com/seattlerb/rubyinline). In fact, the code that calls the C compiler is based on rubyinline.

## Current Status

The project is in very early stages -- today it can only compile extremely primitive functions (basically only one line numeric computations).
