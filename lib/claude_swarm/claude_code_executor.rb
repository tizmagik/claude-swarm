# frozen_string_literal: true

require "json"
require "open3"
require "logger"
require "fileutils"

module ClaudeSwarm
  class ClaudeCodeExecutor
    SWARM_DIR = ".claude-swarm"
    SESSIONS_DIR = "sessions"

    attr_reader :session_id, :last_response, :working_directory, :logger, :session_timestamp

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false, instance_name: nil, calling_instance: nil)
      @working_directory = working_directory
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = nil
      @last_response = nil
      @instance_name = instance_name
      @calling_instance = calling_instance

      # Setup logging
      setup_logging
    end

    def execute(prompt, options = {})
      # Log the request
      log_request(prompt, options)

      cmd_array = build_command_array(prompt, options)

      # Variables to collect output
      stderr_output = []
      result_response = nil

      # Execute command with streaming
      Open3.popen3(*cmd_array, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
        stdin.close

        # Read stderr in a separate thread
        stderr_thread = Thread.new do
          stderr.each_line { |line| stderr_output << line }
        end

        # Process stdout line by line
        stdout.each_line do |line|
          json_data = JSON.parse(line.strip)

          # Log each JSON event
          log_streaming_event(json_data)

          # Capture session_id from system init
          @session_id = json_data["session_id"] if json_data["type"] == "system" && json_data["subtype"] == "init"

          # Capture the final result
          result_response = json_data if json_data["type"] == "result"
        rescue JSON::ParserError => e
          @logger.warn("Failed to parse JSON line: #{line.strip} - #{e.message}")
        end

        # Wait for stderr thread to finish
        stderr_thread.join

        # Check exit status
        exit_status = wait_thread.value
        unless exit_status.success?
          error_msg = stderr_output.join
          @logger.error("Execution error for #{@instance_name}: #{error_msg}")
          raise ExecutionError, "Claude Code execution failed: #{error_msg}"
        end
      end

      # Ensure we got a result
      raise ParseError, "No result found in stream output" unless result_response

      @last_response = result_response

      # Log the final response
      log_response(result_response)

      result_response
    rescue StandardError => e
      @logger.error("Unexpected error for #{@instance_name}: #{e.class} - #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.join("\n")}")
      raise
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

    def setup_logging
      # Use environment variable for session timestamp if available (set by orchestrator)
      # Otherwise create a new timestamp
      @session_timestamp = ENV["CLAUDE_SWARM_SESSION_TIMESTAMP"] || Time.now.strftime("%Y%m%d_%H%M%S")

      # Ensure the session directory exists
      session_dir = File.join(Dir.pwd, SWARM_DIR, SESSIONS_DIR, @session_timestamp)
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

      @logger.info("Started Claude Code executor for instance: #{@instance_name}") if @instance_name
    end

    def log_request(prompt, options)
      log_entry = {
        timestamp: Time.now.utc.iso8601,
        from_instance: @calling_instance,
        to_instance: @instance_name,
        model: @model,
        working_directory: @working_directory,
        session_id: @session_id,
        request: {
          prompt: prompt,
          new_session: options[:new_session] || false,
          system_prompt: options[:system_prompt],
          allowed_tools: options[:allowed_tools]
        }
      }

      @logger.info("REQUEST: #{JSON.pretty_generate(log_entry)}")
    end

    def log_response(response)
      response_entry = {
        timestamp: Time.now.utc.iso8601,
        from_instance: @instance_name,
        to_instance: @calling_instance,
        session_id: @session_id,
        response: {
          result: response["result"],
          cost_usd: response["cost_usd"],
          duration_ms: response["duration_ms"],
          is_error: response["is_error"],
          total_cost: response["total_cost"]
        }
      }

      @logger.info("RESPONSE: #{JSON.pretty_generate(response_entry)}")
    end

    def log_streaming_event(event)
      # Create a compact log entry for streaming events
      log_entry = {
        timestamp: Time.now.utc.iso8601,
        type: event["type"],
        session_id: event["session_id"]
      }

      # Add specific details based on event type
      case event["type"]
      when "system"
        log_entry[:subtype] = event["subtype"]
        log_entry[:tools] = event["tools"] if event["tools"]
        log_entry[:mcp_servers] = event["mcp_servers"] if event["mcp_servers"]
      when "assistant"
        if event["message"]
          msg = event["message"]
          log_entry[:message_id] = msg["id"]
          log_entry[:model] = msg["model"]

          # Extract content summary
          log_entry[:content] = extract_content_summary(msg["content"]) if msg["content"]

          log_entry[:stop_reason] = msg["stop_reason"] if msg["stop_reason"]
          log_entry[:usage] = msg["usage"] if msg["usage"]
        end
      when "user"
        extract_user_event_data(event, log_entry)
      when "result"
        log_entry[:subtype] = event["subtype"]
        log_entry[:cost_usd] = event["cost_usd"]
        log_entry[:duration_ms] = event["duration_ms"]
        log_entry[:is_error] = event["is_error"]
        log_entry[:num_turns] = event["num_turns"]
      end

      @logger.info("STREAM_EVENT: #{JSON.generate(log_entry)}")
    end

    def extract_content_summary(content)
      content.map do |c|
        case c["type"]
        when "text"
          text = c["text"] || ""
          { type: "text", preview: text[0..100] + (text.length > 100 ? "..." : "") }
        when "tool_use"
          { type: "tool_use", tool: c["name"], id: c["id"] }
        else
          { type: c["type"] }
        end
      end
    end

    def extract_user_event_data(event, log_entry)
      return unless event["message"] && event["message"]["content"]

      content = event["message"]["content"]
      return unless content.is_a?(Array) && !content.empty?

      first_item = content.first
      return unless first_item["type"] == "tool_result"

      content_text = first_item["content"] || ""
      log_entry[:tool_result] = {
        tool_use_id: first_item["tool_use_id"],
        preview: content_text[0..100] + (content_text.length > 100 ? "..." : "")
      }
    end

    def build_command_array(prompt, options)
      cmd_array = ["claude"]

      # Add model if specified
      cmd_array += ["--model", @model]

      cmd_array << "--verbose"

      # Add MCP config if specified
      cmd_array += ["--mcp-config", @mcp_config] if @mcp_config

      # Resume session if we have a session ID
      cmd_array += ["--resume", @session_id] if @session_id && !options[:new_session]

      # Always use JSON output format for structured responses
      cmd_array += ["--output-format", "stream-json"]

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
