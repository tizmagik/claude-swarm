# frozen_string_literal: true

module ClaudeSwarm
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
end
