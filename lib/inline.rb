#!/usr/local/bin/ruby -w

##
# Derived from https://github.com/seattlerb/rubyinline with significant modifications
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

require "rbconfig"
require "digest/md5"
require 'fileutils'
require 'rubygems'

$TESTING = false unless defined? $TESTING

class CompilationError < RuntimeError; end

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

  class C
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

    def initialize(target_class, code)
      @target_class = target_class
      @flags = []
      @libs = []
      @code = code
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
    # Adds linker flags to the link command line.  No preprocessing is
    # done, so you must have all your dashes and everything.

    def add_link_flags(*flags)
      @libs.push(*flags)
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
