# frozen_string_literal: true

require "fast_mcp"
require "json"
require "fileutils"
require "logger"
require_relative "claude_code_executor"

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

    public

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

    class TaskTool < FastMcp::Tool
      tool_name "task"
      description "Execute a task using Claude Code"

      arguments do
        required(:prompt).filled(:string).description("The task or question for the agent")
        optional(:new_session).filled(:bool).description("Start a new session (default: false)")
        optional(:system_prompt).filled(:string).description("Override the system prompt for this request")
      end

      def call(prompt:, new_session: false, system_prompt: nil)
        executor = ClaudeMcpServer.executor
        instance_config = ClaudeMcpServer.instance_config
        logger = ClaudeMcpServer.logger

        options = {
          new_session: new_session,
          system_prompt: system_prompt || instance_config[:prompt]
        }

        # Add allowed tools from instance config
        options[:allowed_tools] = instance_config[:tools] if instance_config[:tools]&.any?

        begin
          # Log the request
          log_entry = {
            timestamp: Time.now.utc.iso8601,
            from_instance: ClaudeMcpServer.calling_instance, # The instance making the request
            to_instance: instance_config[:name], # This instance is receiving the request
            model: instance_config[:model],
            working_directory: instance_config[:directory],
            session_id: executor.session_id,
            request: {
              prompt: prompt,
              new_session: new_session,
              system_prompt: options[:system_prompt],
              allowed_tools: options[:allowed_tools]
            }
          }

          logger.info("REQUEST: #{JSON.pretty_generate(log_entry)}")

          response = executor.execute(prompt, options)

          # Log the response
          response_entry = {
            timestamp: Time.now.utc.iso8601,
            from_instance: instance_config[:name], # This instance is sending the response
            to_instance: ClaudeMcpServer.calling_instance, # The instance that made the request receives the response
            session_id: executor.session_id, # Update with new session ID if changed
            response: {
              result: response["result"],
              cost_usd: response["cost_usd"],
              duration_ms: response["duration_ms"],
              is_error: response["is_error"],
              total_cost: response["total_cost"]
            }
          }

          logger.info("RESPONSE: #{JSON.pretty_generate(response_entry)}")

          # Return just the result text as expected by MCP
          response["result"]
        rescue ClaudeCodeExecutor::ExecutionError => e
          logger.error("Execution error for #{instance_config[:name]}: #{e.message}")
          raise StandardError, "Execution failed: #{e.message}"
        rescue ClaudeCodeExecutor::ParseError => e
          logger.error("Parse error for #{instance_config[:name]}: #{e.message}")
          raise StandardError, "Parse error: #{e.message}"
        rescue StandardError => e
          logger.error("Unexpected error for #{instance_config[:name]}: #{e.class} - #{e.message}")
          logger.error("Backtrace: #{e.backtrace.join("\n")}")
          raise StandardError, "Unexpected error: #{e.message}"
        end
      end
    end

    class SessionInfoTool < FastMcp::Tool
      tool_name "session_info"
      description "Get information about the current Claude session for this agent"

      arguments do
        # No arguments needed
      end

      def call
        executor = ClaudeMcpServer.executor

        {
          has_session: executor.has_session?,
          session_id: executor.session_id,
          working_directory: executor.working_directory
        }
      end
    end

    class ResetSessionTool < FastMcp::Tool
      tool_name "reset_session"
      description "Reset the Claude session for this agent, starting fresh on the next task"

      arguments do
        # No arguments needed
      end

      def call
        executor = ClaudeMcpServer.executor
        executor.reset_session

        {
          success: true,
          message: "Session has been reset"
        }
      end
    end
  end
end
