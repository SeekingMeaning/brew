# typed: false
# frozen_string_literal: true

require "open3"
require "ostruct"
require "plist"
require "shellwords"

require "extend/io"
require "extend/predicable"
require "extend/hash_validator"
using HashValidator

# Class for running sub-processes and capturing their output and exit status.
#
# @api private
class SystemCommand
  # Helper functions for calling {SystemCommand.run}.
  module Mixin
    def system_command(*args)
      SystemCommand.run(*args)
    end

    def system_command!(*args)
      SystemCommand.run!(*args)
    end
  end

  include Context
  extend Predicable

  attr_reader :pid

  def self.run(executable, **options)
    new(executable, **options).run!
  end

  def self.run!(command, **options)
    run(command, **options, must_succeed: true)
  end

  def run!
    puts redact_secrets(command.shelljoin.gsub('\=', "="), @secrets) if verbose? || debug?

    @output = []

    each_output_line do |type, line|
      case type
      when :stdout
        $stdout << line if print_stdout?
        @output << [:stdout, line]
      when :stderr
        $stderr << line if print_stderr?
        @output << [:stderr, line]
      end
    end

    result = Result.new(command, @output, @status, secrets: @secrets)
    result.assert_success! if must_succeed?
    result
  end

  def initialize(executable, args: [], sudo: false, env: {}, input: [], must_succeed: false,
                 print_stdout: false, print_stderr: true, verbose: false, secrets: [], **options)
    require "extend/ENV"
    @executable = executable
    @args = args
    @sudo = sudo
    @input = Array(input)
    @print_stdout = print_stdout
    @print_stderr = print_stderr
    @verbose = verbose
    @secrets = (Array(secrets) + ENV.sensitive_environment.values).uniq
    @must_succeed = must_succeed
    options.assert_valid_keys!(:chdir)
    @options = options
    @env = env

    @env.each_key do |name|
      next if /^[\w&&\D]\w*$/.match?(name)

      raise ArgumentError, "Invalid variable name: '#{name}'"
    end
  end

  def command
    [*sudo_prefix, *env_args, executable.to_s, *expanded_args]
  end

  private

  attr_reader :executable, :args, :input, :options, :env

  attr_predicate :sudo?, :print_stdout?, :print_stderr?, :must_succeed?

  def verbose?
    return super if @verbose.nil?

    @verbose
  end

  def env_args
    set_variables = env.compact.map do |name, value|
      sanitized_name = Shellwords.escape(name)
      sanitized_value = Shellwords.escape(value)
      "#{sanitized_name}=#{sanitized_value}"
    end

    return [] if set_variables.empty?

    ["/usr/bin/env", *set_variables]
  end

  def sudo_prefix
    return [] unless sudo?

    askpass_flags = ENV.key?("SUDO_ASKPASS") ? ["-A"] : []
    ["/usr/bin/sudo", *askpass_flags, "-E", "--"]
  end

  def expanded_args
    @expanded_args ||= args.map do |arg|
      if arg.respond_to?(:to_path)
        File.absolute_path(arg)
      elsif arg.is_a?(Integer) || arg.is_a?(Float) || arg.is_a?(URI)
        arg.to_s
      else
        arg.to_str
      end
    end
  end

  def each_output_line(&b)
    executable, *args = command

    raw_stdin, raw_stdout, raw_stderr, raw_wait_thr =
      Open3.popen3(env, [executable, executable], *args, **options)
    @pid = raw_wait_thr.pid

    write_input_to(raw_stdin)
    raw_stdin.close_write
    each_line_from [raw_stdout, raw_stderr], &b

    @status = raw_wait_thr.value
  rescue SystemCallError => e
    @status = $CHILD_STATUS
    @output << [:stderr, e.message]
  end

  def write_input_to(raw_stdin)
    input.each(&raw_stdin.method(:write))
  end

  def each_line_from(sources)
    loop do
      readable_sources, = IO.select(sources)

      readable_sources = readable_sources.reject(&:eof?)

      break if readable_sources.empty?

      readable_sources.each do |source|
        line = source.readline_nonblock || ""
        type = (source == sources[0]) ? :stdout : :stderr
        yield(type, line)
      rescue IO::WaitReadable, EOFError
        next
      end
    end

    sources.each(&:close_read)
  end

  # Result containing the output and exit status of a finished sub-process.
  class Result
    include Context

    attr_accessor :command, :status, :exit_status

    def initialize(command, output, status, secrets:)
      @command       = command
      @output        = output
      @status        = status
      @exit_status   = status.exitstatus
      @secrets       = secrets
    end

    def assert_success!
      return if @status.success?

      raise ErrorDuringExecution.new(command, status: @status, output: @output, secrets: @secrets)
    end

    def stdout
      @stdout ||= @output.select { |type,| type == :stdout }
                         .map { |_, line| line }
                         .join
    end

    def stderr
      @stderr ||= @output.select { |type,| type == :stderr }
                         .map { |_, line| line }
                         .join
    end

    def merged_output
      @merged_output ||= @output.map { |_, line| line }
                                .join
    end

    def success?
      return false if @exit_status.nil?

      @exit_status.zero?
    end

    def to_ary
      [stdout, stderr, status]
    end

    def plist
      @plist ||= begin
        output = stdout

        if /\A(?<garbage>.*?)<\?\s*xml/m =~ output
          output = output.sub(/\A#{Regexp.escape(garbage)}/m, "")
          warn_plist_garbage(garbage)
        end

        if %r{<\s*/\s*plist\s*>(?<garbage>.*?)\Z}m =~ output
          output = output.sub(/#{Regexp.escape(garbage)}\Z/, "")
          warn_plist_garbage(garbage)
        end

        Plist.parse_xml(output)
      end
    end

    def warn_plist_garbage(garbage)
      return unless verbose?
      return unless garbage.match?(/\S/)

      opoo "Received non-XML output from #{Formatter.identifier(command.first)}:"
      $stderr.puts garbage.strip
    end
    private :warn_plist_garbage
  end
end

# Make `system_command` available everywhere.
# FIXME: Include this explicitly only where it is needed.
include SystemCommand::Mixin # rubocop:disable Style/MixinUsage
