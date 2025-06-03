# frozen_string_literal: true

require "json"
require "fast_mcp"
require "logger"
require "fileutils"
require_relative "permission_tool"

module ClaudeSwarm
  class PermissionMcpServer
    SWARM_DIR = ".claude-swarm"
    SESSIONS_DIR = "sessions"

    def initialize(allowed_tools: nil, disallowed_tools: nil)
      @allowed_tools = allowed_tools
      @disallowed_tools = disallowed_tools
      setup_logging
    end

    def start
      # Parse allowed and disallowed tools
      allowed_patterns = parse_tool_patterns(@allowed_tools)
      disallowed_patterns = parse_tool_patterns(@disallowed_tools)

      @logger.info("Starting permission MCP server with allowed patterns: #{allowed_patterns.inspect}, " \
                   "disallowed patterns: #{disallowed_patterns.inspect}")

      # Set the patterns on the tool class
      PermissionTool.allowed_patterns = allowed_patterns
      PermissionTool.disallowed_patterns = disallowed_patterns
      PermissionTool.logger = @logger

      server = FastMcp::Server.new(
        name: "claude-swarm-permissions",
        version: "1.0.0"
      )

      # Register the tool class
      server.register_tool(PermissionTool)

      @logger.info("Permission MCP server started successfully")

      # Start the stdio server
      server.start
    end

    private

    def setup_logging
      # Use environment variable for session timestamp if available
      # Otherwise create a new timestamp
      session_timestamp = ENV["CLAUDE_SWARM_SESSION_TIMESTAMP"] || Time.now.strftime("%Y%m%d_%H%M%S")

      # Ensure the session directory exists
      session_dir = File.join(Dir.pwd, SWARM_DIR, SESSIONS_DIR, session_timestamp)
      FileUtils.mkdir_p(session_dir)

      # Create logger with permissions.log filename
      log_path = File.join(session_dir, "permissions.log")
      @logger = Logger.new(log_path)
      @logger.level = Logger::DEBUG

      # Custom formatter for better readability
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end

      @logger.info("Permission MCP server logging initialized")
    end

    def parse_tool_patterns(tools)
      return [] if tools.nil? || tools.empty?

      # Handle both string and array inputs
      tool_list = tools.is_a?(Array) ? tools : tools.split(/[,\s]+/)

      # Clean up and return
      tool_list.map(&:strip).reject(&:empty?)
    end
  end
end
