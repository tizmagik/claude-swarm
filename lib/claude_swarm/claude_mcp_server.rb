# frozen_string_literal: true

require "fast_mcp"
require "json"
require "fileutils"
require "logger"
require_relative "claude_code_executor"
require_relative "task_tool"
require_relative "session_info_tool"
require_relative "reset_session_tool"

module ClaudeSwarm
  class ClaudeMcpServer
    SWARM_DIR = ".claude-swarm"
    SESSIONS_DIR = "sessions"

    # Class variables to share state with tool classes
    class << self
      attr_accessor :executor, :instance_config, :logger, :session_timestamp, :calling_instance
    end

    def initialize(instance_config, calling_instance:)
      @instance_config = instance_config
      @calling_instance = calling_instance
      @executor = ClaudeCodeExecutor.new(
        working_directory: instance_config[:directory],
        model: instance_config[:model],
        mcp_config: instance_config[:mcp_config_path],
        vibe: instance_config[:vibe]
      )

      # Setup logging
      setup_logging

      # Set class variables so tools can access them
      self.class.executor = @executor
      self.class.instance_config = @instance_config
      self.class.logger = @logger
      self.class.calling_instance = @calling_instance
    end

    def start
      server = FastMcp::Server.new(
        name: @instance_config[:name],
        version: "1.0.0"
      )

      # Set dynamic description for TaskTool based on instance config
      if @instance_config[:description]
        TaskTool.description "Execute a task using Agent #{@instance_config[:name]}. #{@instance_config[:description]}"
      else
        TaskTool.description "Execute a task using Agent #{@instance_config[:name]}"
      end

      # Register tool classes (not instances)
      server.register_tool(TaskTool)
      server.register_tool(SessionInfoTool)
      server.register_tool(ResetSessionTool)

      # Start the stdio server
      server.start
    end

    private

    def setup_logging
      # Use environment variable for session timestamp if available (set by orchestrator)
      # Otherwise create a new timestamp
      self.class.session_timestamp ||= ENV["CLAUDE_SWARM_SESSION_TIMESTAMP"] || Time.now.strftime("%Y%m%d_%H%M%S")

      # Ensure the session directory exists
      session_dir = File.join(Dir.pwd, SWARM_DIR, SESSIONS_DIR, self.class.session_timestamp)
      FileUtils.mkdir_p(session_dir)

      # Create logger with session.log filename
      log_filename = "session.log"
      log_path = File.join(session_dir, log_filename)
      @logger = Logger.new(log_path)
      @logger.level = Logger::INFO

      # Custom formatter for better readability
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end

      @logger.info("Started MCP server for instance: #{@instance_config[:name]}")
    end
  end
end
