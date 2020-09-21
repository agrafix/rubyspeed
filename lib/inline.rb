#!/usr/local/bin/ruby -w

##
# Taken from https://github.com/seattlerb/rubyinline
# Slightly modified to work for this project
#
# (The MIT License)

# Copyright (c) Ryan Davis, seattle.rb

# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
##

##
# Ruby Inline is a framework for writing ruby extensions in foreign
# languages.
#
# == SYNOPSIS
#
#   require 'inline'
#   class MyClass
#     inline do |builder|
#       builder.include "<math.h>"
#       builder.c %q{
#         long factorial(int max) {
#           int i=max, result=1;
#           while (i >= 2) { result *= i--; }
#           return result;
#         }
#       }
#     end
#   end
#
# == DESCRIPTION
#
# Inline allows you to write foreign code within your ruby code. It
# automatically determines if the code in question has changed and
# builds it only when necessary. The extensions are then automatically
# loaded into the class/module that defines it.
#
# You can even write extra builders that will allow you to write
# inlined code in any language. Use Inline::C as a template and look
# at Module#inline for the required API.
#
# == PACKAGING
#
# To package your binaries into a gem, use hoe's INLINE and
# FORCE_PLATFORM env vars.
#
# Example:
#
#   rake package INLINE=1
#
# or:
#
#   rake package INLINE=1 FORCE_PLATFORM=mswin32
#
# See hoe for more details.
#

require "rbconfig"
require "digest/md5"
require 'fileutils'
require 'rubygems'

$TESTING = false unless defined? $TESTING

class CompilationError < RuntimeError; end

# See https://github.com/seattlerb/zentest/blob/54ab05acab020ea728d5911221367ff51e0ca849/lib/zentest_mapping.rb
# Also used under MIT license Copyright (c) Ryan Davis, Eric Hodel, seattle.rb
module ZenTestMapping

  @@orig_method_map = {
    '!'   => 'bang',
    '%'   => 'percent',
    '&'   => 'and',
    '*'   => 'times',
    '**'  => 'times2',
    '+'   => 'plus',
    '-'   => 'minus',
    '/'   => 'div',
    '<'   => 'lt',
    '<='  => 'lte',
    '<=>' => 'spaceship',
    "<\<" => 'lt2',
    '=='  => 'equals2',
    '===' => 'equals3',
    '=~'  => 'equalstilde',
    '>'   => 'gt',
    '>='  => 'ge',
    '>>'  => 'gt2',
    '+@'  => 'unary_plus',
    '-@'  => 'unary_minus',
    '[]'  => 'index',
    '[]=' => 'index_equals',
    '^'   => 'carat',
    '|'   => 'or',
    '~'   => 'tilde',
  }

  @@method_map = @@orig_method_map.merge(@@orig_method_map.invert)

  @@mapped_re = @@orig_method_map.values.sort_by { |k| k.length }.map {|s|
    Regexp.escape(s)
  }.reverse.join("|")

  def munge name
    name = name.to_s.dup

    is_cls_method = name.sub!(/^self\./, '')

    name = @@method_map[name] if @@method_map.has_key? name
    name = name.sub(/=$/, '_equals')
    name = name.sub(/\?$/, '_eh')
    name = name.sub(/\!$/, '_bang')

    name = yield name if block_given?

    name = "class_" + name if is_cls_method

    name
  end

  # Generates a test method name from a normal method,
  # taking into account names composed of metacharacters
  # (used for arithmetic, etc
  def normal_to_test name
    "test_#{munge name}"
  end

  def unmunge name
    name = name.to_s.dup

    is_cls_method = name.sub!(/^class_/, '')

    name = name.sub(/_equals(_.*)?$/, '=') unless name =~ /index/
    name = name.sub(/_bang(_.*)?$/, '!')
    name = name.sub(/_eh(_.*)?$/, '?')
    name = name.sub(/^(#{@@mapped_re})(_.*)?$/) {$1}
    name = yield name if block_given?
    name = @@method_map[name] if @@method_map.has_key? name
    name = 'self.' + name if is_cls_method

    name
  end

  # Converts a method name beginning with test to its
  # corresponding normal method name, taking into account
  # symbolic names which may have been anglicised by
  # #normal_to_test().
  def test_to_normal(name, klassname=nil)
    unmunge(name.to_s.sub(/^test_/, '')) do |n|
      if defined? @inherited_methods then
        known_methods = (@inherited_methods[klassname] || {}).keys.sort.reverse
        known_methods_re = known_methods.map {|s| Regexp.escape(s) }.join("|")
        n = n.sub(/^(#{known_methods_re})(_.*)?$/) { $1 } unless
          known_methods_re.empty?
        n
      end
    end
  end
end

##
# The Inline module is the top-level module used. It is responsible
# for instantiating the builder for the right language used,
# compilation/linking when needed, and loading the inlined code into
# the current namespace.

module Inline
  VERSION = "4.0.0"

  WINDOWS  = /mswin|mingw/ =~ RUBY_PLATFORM
  RUBINIUS = defined? RUBY_ENGINE
  DEV_NULL = (WINDOWS ? 'nul'      : '/dev/null')
  GEM      = 'gem'
  RAKE     = if RUBINIUS then
               File.join(Gem.bindir, 'rake')
             else
               "#{Gem.ruby} -S rake"
             end

  warn "RubySpeed v #{VERSION}" if $DEBUG

  # rootdir can be forced using INLINEDIR variable
  # if not defined, it should store in user HOME folder
  #
  # Under Windows user data can be stored in several locations:
  #
  #  HOME
  #  HOMEDRIVE + HOMEPATH
  #  APPDATA
  #  USERPROFILE
  #
  # Perform a check in that other to see if the environment is defined
  # and if so, use it. only try this on Windows.
  #
  # Note, depending on how you're using this (eg, a rails app in
  # production), you probably want to use absolute paths.

  def self.rootdir
    env = ENV['INLINEDIR'] || ENV['HOME']

    if env.nil? and WINDOWS then
      # try HOMEDRIVE + HOMEPATH combination
      if ENV['HOMEDRIVE'] && ENV['HOMEPATH'] then
        env = ENV['HOMEDRIVE'] + ENV['HOMEPATH']
      end

      # no HOMEDRIVE? use APPDATA
      env = ENV['APPDATA'] if env.nil? and ENV['APPDATA']

      # bummer, still no env? then fall to USERPROFILE
      env = ENV['USERPROFILE'] if env.nil? and ENV['USERPROFILE']
    end

    if env.nil? then
      abort "Define INLINEDIR or HOME in your environment and try again"
    end

    unless defined? @@rootdir and env == @@rootdir and test ?d, @@rootdir then
      rootdir = env
      Dir.mkdir rootdir, 0700 unless test ?d, rootdir
      Dir.assert_secure rootdir
      @@rootdir = rootdir
    end

    @@rootdir
  end

  def self.directory
    unless defined? @@directory then
      version = "#{Gem.ruby_engine}-#{RbConfig::CONFIG['ruby_version']}"

      @@directory = File.join(self.rootdir, ".rubyspeed_cache", version)
    end

    Dir.assert_secure @@directory

    @@directory
  end

  ##
  # Inline::C is the default builder used and the only one provided by
  # Inline. It can be used as a template to write builders for other
  # languages. It understands type-conversions for the basic types and
  # can be extended as needed using #add_type_converter, #alias_type_converter
  # and #remove_type_converter.

  class C

    include ZenTestMapping

    MAGIC_ARITY_THRESHOLD = 15
    MAGIC_ARITY = -1

    ##
    # Default C to ruby and ruby to C type map

    TYPE_MAP = {
      'char'               => [ 'NUM2CHR',        'CHR2FIX'      ],

      'char *'             => [ 'StringValuePtr', 'rb_str_new2'  ],

      'double'             => [ 'NUM2DBL',        'rb_float_new' ],

      'int'                => [ "FI\X2INT",       'INT2FIX'      ],
      'unsigned int'       => [ 'NUM2UINT',       'UINT2NUM'     ],
      'unsigned'           => [ 'NUM2UINT',       'UINT2NUM'     ],

      'long'               => [ 'NUM2LONG',       'LONG2NUM'     ],
      'unsigned long'      => [ 'NUM2ULONG',      'ULONG2NUM'    ],

      'long long'          => [ 'NUM2LL',         'LL2NUM'       ],
      'unsigned long long' => [ 'NUM2ULL',        'ULL2NUM'      ],

      'off_t'              => [ 'NUM2OFFT',       'OFFT2NUM'     ],

      'VALUE'              => [ '',               ''             ],
      # Can't do these converters because they conflict with the above:
      # ID2SYM(x), SYM2ID(x), F\IX2UINT(x)
    }

    def module_name
      @target_class
    end

    def so_name
      unless defined? @so_name then
        @so_name = "#{Inline.directory}/#{module_name}.#{RbConfig::CONFIG["DLEXT"]}"
      end
      @so_name
    end

    attr_reader :target_class
    attr_writer :target_class
    attr_accessor :flags, :libs

    ##
    # Sets the name of the C struct for generating accessors.  Used with
    # #accessor, #reader, #writer.

    attr_accessor :struct_name

    def initialize(target_class, code)
      @target_class = target_class
      @flags = []
      @libs = []
      @include_ruby_first = true
      @inherited_methods = {}
      @struct_name = nil
      @code = code

      @type_map = TYPE_MAP.dup
    end

    ##
    # Converts ruby type +type+ to a C type

    def ruby2c(type)
      raise ArgumentError, "Unknown type #{type.inspect}" unless @type_map.has_key? type
      @type_map[type].first
    end

    ##
    # Converts C type +type+ to a ruby type

    def c2ruby(type)
      raise ArgumentError, "Unknown type #{type.inspect}" unless @type_map.has_key? type
      @type_map[type].last
    end

    ##
    # Attempts to load pre-generated code returning true if it succeeds.

    def load_cache
      begin
        file = File.join("inline", File.basename(so_name))
        if require file then
          dir = Inline.directory
          warn "WAR\NING: #{dir} exists but is not being used" if test ?d, dir and $VERBOSE
          return true
        end
      rescue LoadError
      end
      return false
    end

    ##
    # Loads the generated code back into ruby

    def load
      require "#{so_name}"
    end

    ##
    # Builds the source file, if needed, and attempts to compile it.

    def build
      so_name = self.so_name
      so_exists = File.file? so_name
      
      unless  File.directory? Inline.directory then
        warn "NOTE: creating #{Inline.directory} for RubyInline" if $DEBUG
        FileUtils.mkdir_p Inline.directory, :mode => 0700
      end

      src_name = "#{Inline.directory}/#{module_name}.c"
      old_src_name = "#{src_name}.old"
      should_compare = File.write_with_backup(src_name) do |io|
        io.puts(@code)
      end

      # recompile only if the files are different
      recompile = true
      if so_exists and should_compare and FileUtils.compare_file(old_src_name, src_name)
        recompile = false

        # Updates the timestamps on all the generated/compiled files.
        # Prevents us from entering this conditional unless the source
        # file changes again.
        t = Time.now
        File.utime(t, t, src_name, old_src_name, so_name)
      end

      if recompile
        hdrdir = %w(srcdir includedir archdir rubyhdrdir).map { |name|
          RbConfig::CONFIG[name]
        }.find { |dir|
          dir and File.exist? File.join(dir, "ruby.h")
        } or abort "ERROR: Can't find header dir for ruby. Exiting..."

        flags = @flags.join(' ')
        libs  = @libs.join(' ')

        config_hdrdir =
          if RbConfig::CONFIG['rubyarchhdrdir'] then
            "-I #{RbConfig::CONFIG['rubyarchhdrdir']}"
          elsif RUBY_VERSION > '1.9' then
            "-I #{File.join hdrdir, RbConfig::CONFIG['arch']}"
          else
            nil
          end

        windows = WINDOWS and RUBY_PLATFORM =~ /mswin/
        non_windows = ! windows
        cmd =
          [ RbConfig::CONFIG['LDSHARED'],
            flags,
            "-Ofast",
            (RbConfig::CONFIG['DLDFLAGS']         if non_windows),
            (RbConfig::CONFIG['CCDLFLAGS']        if non_windows),
            RbConfig::CONFIG['CFLAGS'],
            (RbConfig::CONFIG['LDFLAGS']          if non_windows),
            '-I', hdrdir,
            config_hdrdir,
            '-I', RbConfig::CONFIG['includedir'],
            ("-L#{RbConfig::CONFIG['libdir']}"    if non_windows),
            (['-o', so_name.inspect]              if non_windows),
            File.expand_path(src_name).inspect,
            libs,
            cfg_for_windows,
            (RbConfig::CONFIG['LDFLAGS']          if windows),
            (RbConfig::CONFIG['CCDLFLAGS']        if windows),
          ].compact.join(' ')

        # odd compilation error on clang + freebsd 10. Ruby built w/ rbenv.
        cmd = cmd.gsub(/-Wl,-soname,\$@/, "-Wl,-soname,#{File.basename so_name}")

        # strip off some makefile macros for mingw 1.9
        cmd = cmd.gsub(/\$\(.*\)/, '') if RUBY_PLATFORM =~ /mingw/

        cmd += " 2> #{DEV_NULL}" if $TESTING and not $DEBUG

        warn "Building #{so_name} with '#{cmd}'" if $DEBUG

        result =
          if WINDOWS
            Dir.chdir(Inline.directory) { `#{cmd}` }
          else
            `#{cmd}`
          end

        warn "Output:\n#{result}" if $DEBUG

        if $? != 0
          bad_src_name = src_name + ".bad"
          File.rename src_name, bad_src_name
          raise CompilationError, "error executing #{cmd.inspect}: #{$?}\nRenamed #{src_name} to #{bad_src_name}"
        end

        # NOTE: manifest embedding is only required when using VC8 ruby
        # build or compiler.
        # Errors from this point should be ignored if RbConfig::CONFIG['arch']
        # (RUBY_PLATFORM) matches 'i386-mswin32_80'
        if WINDOWS and RUBY_PLATFORM =~ /_80$/
          Dir.chdir Inline.directory do
            cmd = "mt /manifest lib.so.manifest /outputresource:so.dll;#2"
            warn "Embedding manifest with '#{cmd}'" if $DEBUG
            result = `#{cmd}`
            warn "Output:\n#{result}" if $DEBUG
            if $? != 0 then
              raise CompilationError, "error executing #{cmd}: #{$?}"
            end
          end
        end

        warn "Built successfully" if $DEBUG
      end
    end # def build

    ##
    # Returns extra compilation flags for windows platforms.

    def cfg_for_windows
      case RUBY_PLATFORM
      when /mswin32/ then
        " -link /OUT:\"#{self.so_name}\" /LIBPATH:\"#{RbConfig::CONFIG['libdir']}\" /DEFAULTLIB:\"#{RbConfig::CONFIG['LIBRUBY']}\" /INCREMENTAL:no /EXPORT:Init_#{module_name}"
      when /mingw32/ then
        c = RbConfig::CONFIG
        " -Wl,--enable-auto-import -L#{c['libdir']} -l#{c['RUBY_SO_NAME']} -o #{so_name.inspect}"
      when /i386-cygwin/ then
        ' -L/usr/local/lib -lruby.dll'
      else
        ''
      end
    end

    ##
    # Adds compiler options to the compiler command line.  No
    # preprocessing is done, so you must have all your dashes and
    # everything.

    def add_compile_flags(*flags)
      @flags.push(*flags)
    end

    ##
    # Registers a static id_name for the symbol :name.

    def add_id name
      self.add_static "id_#{name}", "rb_intern(\"#{name}\")"
    end

    ##
    # Adds linker flags to the link command line.  No preprocessing is
    # done, so you must have all your dashes and everything.

    def add_link_flags(*flags)
      @libs.push(*flags)
    end

    ##
    # Create a static variable and initialize it to a value.

    def add_static name, init, type = "VALUE"
      prefix      "static #{type} #{name};"
      add_to_init "#{name} = #{init};"
    end

    ##
    # Registers C type-casts +r2c+ and +c2r+ for +type+.

    def add_type_converter(type, r2c, c2r)
      warn "WAR\NING: overridding #{type} on #{caller[0]}" if @type_map.has_key? type
      @type_map[type] = [r2c, c2r]
    end

    ##
    # Registers C type +alias_type+ as an alias of +existing_type+

    def alias_type_converter(existing_type, alias_type)
      warn "WAR\NING: overridding #{type} on #{caller[0]}" if
        @type_map.has_key? alias_type

      @type_map[alias_type] = @type_map[existing_type]
    end

    ##
    # Unregisters C type-casts for +type+.

    def remove_type_converter(type)
      @type_map.delete type
    end

    ##
    # Maps RubyConstants to cRubyConstants.

    def map_ruby_const(*names)
      names.each do |name|
        self.prefix "static VALUE c#{name};"
        self.add_to_init "    c#{name} = rb_const_get(c, rb_intern(#{name.to_s.inspect}));"
      end
    end

    ##
    # Maps a C constant to ruby. +names_and_types+ is a hash that maps the
    # name of the constant to its C type.
    #
    #   builder.map_c_const :C_NAME => :int
    #
    # If you wish to give the constant a different ruby name:
    #
    #   builder.map_c_const :C_NAME => [:int, :RUBY_NAME]

    def map_c_const(names_and_types)
      names_and_types.each do |name, typ|
        typ, ruby_name = Array === typ ? typ : [typ, name]
        self.add_to_init "    rb_define_const(c, #{ruby_name.to_s.inspect}, #{c2ruby(typ.to_s)}(#{name}));"
      end
    end

    ##
    # Specifies that the the ruby.h header should be included *after* custom
    # header(s) instead of before them.

    def include_ruby_last
      @include_ruby_first = false
    end


  end # class Inline::C
end # module Inline

class File

  ##
  # Equivalent to +File::open+ with an associated block, but moves
  # any existing file with the same name to the side first.

  def self.write_with_backup(path) # returns true if file already existed

    # move previous version to the side if it exists
    renamed = false
    if File.file? path then
      begin
        File.rename path, path + ".old"
        renamed = true
      rescue SystemCallError
        # do nothing
      end
    end

    File.open(path, "w") do |io|
      yield(io)
    end

    return renamed
  end
end # class File

class Dir

  ##
  # +assert_secure+ checks that if a +path+ exists it has minimally
  # writable permissions. If not, it prints an error and exits. It
  # only works on +POSIX+ systems. Patches for other systems are
  # welcome.

  def self.assert_secure(path)
    mode = File.stat(path).mode
    unless ((mode % 01000) & 0022) == 0 then
      if $TESTING then
        raise SecurityError, "Directory #{path} is insecure"
      else
        abort "#{path} is insecure (#{'%o' % mode}). It may not be group or world writable. Exiting."
      end
    end
  rescue Errno::ENOENT
    # If it ain't there, it's certainly secure
  end
end
