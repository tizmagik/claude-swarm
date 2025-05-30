# frozen_string_literal: true

require "json"
require "open3"

module ClaudeSwarm
  class ClaudeCodeExecutor
    attr_reader :session_id, :last_response, :working_directory

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false)
      @working_directory = working_directory
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = nil
      @last_response = nil
    end

    def execute(prompt, options = {})
      cmd_array = build_command_array(prompt, options)

      stdout, stderr, status = Open3.capture3(*cmd_array, chdir: @working_directory)

      raise ExecutionError, "Claude Code execution failed: #{stderr}" unless status.success?

      begin
        response = JSON.parse(stdout)
        @last_response = response

        # Extract and store session ID from the response
        @session_id = response["session_id"]

        response
      rescue JSON::ParserError => e
        raise ParseError, "Failed to parse JSON response: #{e.message}\nOutput: #{stdout}"
      end
    end

    def execute_text(prompt, options = {})
      response = execute(prompt, options)
      response["result"] || ""
    end

    def reset_session
      @session_id = nil
      @last_response = nil
    end

    def has_session?
      !@session_id.nil?
    end

    private

    def build_command_array(prompt, options)
      cmd_array = ["claude"]

      # Add model if specified
      cmd_array += ["--model", @model]

      # Add MCP config if specified
      cmd_array += ["--mcp-config", @mcp_config] if @mcp_config

      # Resume session if we have a session ID
      cmd_array += ["--resume", @session_id] if @session_id && !options[:new_session]

      # Always use JSON output format for structured responses
      cmd_array += ["--output-format", "json"]

      # Add non-interactive mode with prompt
      cmd_array += ["--print", "-p", prompt]

      # Add any custom system prompt
      cmd_array += ["--system-prompt", options[:system_prompt]] if options[:system_prompt]

      # Add any allowed tools or vibe flag
      if @vibe
        cmd_array << "--dangerously-skip-permissions"
      elsif options[:allowed_tools]
        tools = Array(options[:allowed_tools]).join(",")
        cmd_array += ["--allowedTools", tools]
      end

      cmd_array
    end

    class ExecutionError < StandardError; end
    class ParseError < StandardError; end
  end
end
