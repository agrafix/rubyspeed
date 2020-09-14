# Rubyspeed

Welcome to Rubyspeed. Right now, Rubyspeed is a very early proof of concept that allows annotating method declarations to automatically be compiled to C. Here's an example:

``` ruby
require 'rubyspeed'

class TestClass
  extend(Rubyspeed::Compiles)
    
  compile!
  def add_two_method(x)
    x + 2
  end
end
```

What this will do is replace the `add_two_method` with a compiled C implementation.

## Inspiration

This project was inspired by [Stephen Diehl's LLVM specializer for Python](http://dev.stephendiehl.com/numpile/) and [rubyinline](https://github.com/seattlerb/rubyinline).

## Current Status

The project is in very early stages -- today it can only compile extremely primitive functions (basically only one line numeric computations).
