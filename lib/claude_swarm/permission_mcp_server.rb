# frozen_string_literal: true

require "json"
require "fast_mcp"
require "logger"
require "fileutils"
require_relative "permission_tool"
require_relative "session_path"
require_relative "process_tracker"

module ClaudeSwarm
  class PermissionMcpServer
    # Server configuration
    SERVER_NAME = "claude-swarm-permissions"
    SERVER_VERSION = "1.0.0"

    # Tool categories
    FILE_TOOLS = %w[Read Write Edit].freeze
    BASH_TOOL = "Bash"

    # Pattern matching
    TOOL_PATTERN_REGEX = /^([^()]+)\(([^)]+)\)$/
    PARAM_PATTERN_REGEX = /^(\w+)\s*:\s*(.+)$/

    def initialize(allowed_tools: nil, disallowed_tools: nil)
      @allowed_tools = allowed_tools
      @disallowed_tools = disallowed_tools
      setup_logging
    end

    def start
      configure_permission_tool
      create_and_start_server
    end

    private

    def configure_permission_tool
      allowed_patterns = parse_tool_patterns(@allowed_tools)
      disallowed_patterns = parse_tool_patterns(@disallowed_tools)

      log_configuration(allowed_patterns, disallowed_patterns)

      PermissionTool.allowed_patterns = allowed_patterns
      PermissionTool.disallowed_patterns = disallowed_patterns
      PermissionTool.logger = @logger
    end

    def create_and_start_server
      # Track this process
      session_path = SessionPath.from_env
      if session_path && File.exist?(session_path)
        tracker = ProcessTracker.new(session_path)
        tracker.track_pid(Process.pid, "mcp_permissions")
      end

      server = FastMcp::Server.new(
        name: SERVER_NAME,
        version: SERVER_VERSION
      )

      server.register_tool(PermissionTool)
      @logger.info("Permission MCP server started successfully")
      server.start
    end

    def setup_logging
      session_path = SessionPath.from_env
      SessionPath.ensure_directory(session_path)
      @logger = create_logger(session_path)
      @logger.info("Permission MCP server logging initialized")
    end

    def create_logger(session_path)
      log_path = File.join(session_path, "permissions.log")
      logger = Logger.new(log_path)
      logger.level = Logger::DEBUG
      logger.formatter = log_formatter
      logger
    end

    def log_formatter
      proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end
    end

    def log_configuration(allowed_patterns, disallowed_patterns)
      @logger.info("Starting permission MCP server with allowed patterns: #{allowed_patterns.inspect}, " \
                   "disallowed patterns: #{disallowed_patterns.inspect}")
    end

    def parse_tool_patterns(tools)
      return [] if tools.nil? || tools.empty?

      normalize_tool_list(tools).filter_map do |tool|
        parse_single_tool_pattern(tool.strip)
      end
    end

    def normalize_tool_list(tools)
      tools.is_a?(Array) ? tools : tools.split(/[,\s]+/)
    end

    def parse_single_tool_pattern(tool)
      return nil if tool.empty?

      if (match = tool.match(TOOL_PATTERN_REGEX))
        parse_tool_with_pattern(match[1], match[2])
      elsif tool.include?("*")
        create_wildcard_tool_pattern(tool)
      else
        create_exact_tool_pattern(tool)
      end
    end

    def parse_tool_with_pattern(tool_name, pattern)
      case tool_name
      when *FILE_TOOLS
        create_file_tool_pattern(tool_name, pattern)
      when BASH_TOOL
        create_bash_tool_pattern(tool_name, pattern)
      else
        create_custom_tool_pattern(tool_name, pattern)
      end
    end

    def create_file_tool_pattern(tool_name, pattern)
      {
        tool_name: tool_name,
        pattern: File.expand_path(pattern),
        type: :glob
      }
    end

    def create_bash_tool_pattern(tool_name, pattern)
      {
        tool_name: tool_name,
        pattern: process_bash_pattern(pattern),
        type: :regex
      }
    end

    def process_bash_pattern(pattern)
      if pattern.include?(":")
        # Colon syntax: convert parts and join with spaces
        pattern.split(":")
               .map { |part| part.gsub("*", ".*") }
               .join(" ")
      else
        # Literal pattern: escape asterisks
        pattern.gsub("*", "\\*")
      end
    end

    def create_custom_tool_pattern(tool_name, pattern)
      {
        tool_name: tool_name,
        pattern: parse_parameter_patterns(pattern),
        type: :params
      }
    end

    def parse_parameter_patterns(pattern)
      pattern.split(",").each_with_object({}) do |param_pair, params|
        param_pair = param_pair.strip
        if (match = param_pair.match(PARAM_PATTERN_REGEX))
          params[match[1]] = match[2]
        end
      end
    end

    def create_wildcard_tool_pattern(tool)
      {
        tool_name: tool.gsub("*", ".*"),
        pattern: nil,
        type: :regex
      }
    end

    def create_exact_tool_pattern(tool)
      {
        tool_name: tool,
        pattern: nil,
        type: :exact
      }
    end
  end
end
