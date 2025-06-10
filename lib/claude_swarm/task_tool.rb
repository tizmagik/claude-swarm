# frozen_string_literal: true

module ClaudeSwarm
  class TaskTool < FastMcp::Tool
    tool_name "task"
    description "Execute a task using Claude Code. There is no description parameter."

    arguments do
      required(:prompt).filled(:string).description("The task or question for the agent")
      optional(:new_session).filled(:bool).description("Start a new session (default: false)")
      optional(:system_prompt).filled(:string).description("Override the system prompt for this request")
    end

    def call(prompt:, new_session: false, system_prompt: nil)
      executor = ClaudeMcpServer.executor
      instance_config = ClaudeMcpServer.instance_config

      options = {
        new_session: new_session,
        system_prompt: system_prompt || instance_config[:prompt]
      }

      # Add allowed tools from instance config
      options[:allowed_tools] = instance_config[:tools] if instance_config[:tools]&.any?

      # Add disallowed tools from instance config
      options[:disallowed_tools] = instance_config[:disallowed_tools] if instance_config[:disallowed_tools]&.any?

      response = executor.execute(prompt, options)

      # Return just the result text as expected by MCP
      response["result"]
    end
  end
end
