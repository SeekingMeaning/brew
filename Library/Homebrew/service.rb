# typed: true
# frozen_string_literal: true

module Homebrew
  # The {Service} class implements the DSL methods used in a formula's
  # `service` block and stores related instance variables. Most of these methods
  # also return the related instance variable when no argument is provided.
  class Service
    extend T::Sig
    extend Forwardable

    RUN_TYPE_IMMEDIATE = "immediate"
    RUN_TYPE_INTERVAL = "interval"
    RUN_TYPE_CRON = "cron"

    def initialize(formula)
      @formula = formula
      @run_type = RUN_TYPE_IMMEDIATE
    end

    sig { params(command: T.nilable(T.any(T::Array[String], String, Pathname))).returns(T.nilable(Array)) }
    def run(command = nil)
      case T.unsafe(command)
      when nil
        @run
      when String, Pathname
        @run = [command]
      when Array
        @run = command
      else
        raise TypeError, "Service#run expects an Array"
      end
    end

    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def working_dir(path = nil)
      case T.unsafe(path)
      when nil
        @working_dir
      when String, Pathname
        @working_dir = path
      else
        raise TypeError, "Service#working_dir expects a String"
      end
    end

    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def log_path(path = nil)
      case T.unsafe(path)
      when nil
        @log_path
      when String, Pathname
        @log_path = path
      else
        raise TypeError, "Service#log_path expects a String"
      end
    end

    sig { params(path: T.nilable(T.any(String, Pathname))).returns(T.nilable(String)) }
    def error_log_path(path = nil)
      case T.unsafe(path)
      when nil
        @error_log_path
      when String, Pathname
        @error_log_path = path
      else
        raise TypeError, "Service#error_log_path expects a String"
      end
    end

    sig { params(value: T.nilable(T::Boolean)).returns(T.nilable(T::Boolean)) }
    def keep_alive(value = nil)
      case T.unsafe(value)
      when nil
        @keep_alive
      when true, false
        @keep_alive = value
      else
        raise TypeError, "Service#keep_alive expects a Boolean"
      end
    end

    sig { params(type: T.nilable(String)).returns(T.nilable(String)) }
    def run_type(type = nil)
      case T.unsafe(type)
      when nil
        @run_type
      when "immediate"
        @run_type = type
      when RUN_TYPE_INTERVAL, RUN_TYPE_CRON
        raise TypeError, "Service#run_type does not support timers"
      when String
        raise TypeError, "Service#run_type allows: '#{RUN_TYPE_IMMEDIATE}'/'#{RUN_TYPE_INTERVAL}'/'#{RUN_TYPE_CRON}'"
      else
        raise TypeError, "Service#run_type expects a string"
      end
    end

    # Returns a `String` plist.
    # @return [String]
    sig { returns(String) }
    def to_plist
      {
        "Label"             => "homebrew.service.#{@formula.name}",
        "KeepAlive"         => @keep_alive,
        "RunAtLoad"         => @run_type == RUN_TYPE_IMMEDIATE,
        "ProgramArguments"  => @run,
        "WorkingDirectory"  => @working_dir,
        "StandardOutPath"   => @log_path,
        "StandardErrorPath" => @error_log_path,
      }.to_plist
    end
  end
end
