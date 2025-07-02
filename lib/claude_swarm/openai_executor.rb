# frozen_string_literal: true

require "json"
require "logger"
require "fileutils"
require "openai"
require "mcp_client"
require "securerandom"

module ClaudeSwarm
  class OpenAIExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
                   instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
                   claude_session_id: nil, additional_directories: [],
                   temperature: 0.3, api_version: "chat_completion", openai_token_env: "OPENAI_API_KEY",
                   base_url: nil)
      @working_directory = working_directory
      @additional_directories = additional_directories
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = claude_session_id
      @last_response = nil
      @instance_name = instance_name
      @instance_id = instance_id
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @temperature = temperature
      @api_version = api_version
      @base_url = base_url

      # Conversation state for maintaining context
      @conversation_messages = []
      @previous_response_id = nil

      # Setup logging first
      setup_logging

      # Setup OpenAI client
      setup_openai_client(openai_token_env)

      # Setup MCP client for tools
      setup_mcp_client
    end

    def execute(prompt, options = {})
      # Log the request
      log_request(prompt)

      # Start timing
      start_time = Time.now

      # Execute based on API version
      result = if @api_version == "responses"
                 execute_responses_api(prompt, options)
               else
                 execute_chat_api(prompt, options)
               end

      # Calculate duration
      duration_ms = ((Time.now - start_time) * 1000).round

      # Format response similar to ClaudeCodeExecutor
      response = {
        "type" => "result",
        "result" => result,
        "duration_ms" => duration_ms,
        "total_cost" => calculate_cost(result),
        "session_id" => @session_id
      }

      log_response(response)

      @last_response = response
      response
    rescue StandardError => e
      @logger.error("Unexpected error for #{@instance_name}: #{e.class} - #{e.message}")
      @logger.error("Backtrace: #{e.backtrace.join("\n")}")
      raise
    end

    def reset_session
      @session_id = nil
      @last_response = nil
      @conversation_messages = []
      @previous_response_id = nil
    end

    def has_session?
      !@session_id.nil?
    end

    private

    def setup_openai_client(token_env)
      config = {
        access_token: ENV.fetch(token_env),
        log_errors: true
      }
      config[:uri_base] = @base_url if @base_url

      @openai_client = OpenAI::Client.new(config)
    rescue KeyError
      raise ExecutionError, "OpenAI API key not found in environment variable: #{token_env}"
    end

    def setup_mcp_client
      return unless @mcp_config && File.exist?(@mcp_config)

      # Read MCP config to find MCP servers
      mcp_data = JSON.parse(File.read(@mcp_config))

      # Create MCP client with all MCP servers from the config
      if mcp_data["mcpServers"] && !mcp_data["mcpServers"].empty?
        mcp_configs = []

        mcp_data["mcpServers"].each do |name, server_config|
          case server_config["type"]
          when "stdio"
            # Combine command and args into a single array
            command_array = [server_config["command"]]
            command_array.concat(server_config["args"] || [])

            mcp_configs << MCPClient.stdio_config(
              command: command_array,
              name: name
            )
          when "sse"
            @logger.warn("SSE MCP servers not yet supported for OpenAI instances: #{name}")
            # TODO: Add SSE support when available in ruby-mcp-client
          end
        end

        if mcp_configs.any?
          @mcp_client = MCPClient.create_client(
            mcp_server_configs: mcp_configs,
            logger: @logger
          )

          # List available tools from all MCP servers
          begin
            @available_tools = @mcp_client.list_tools
            @logger.info("Loaded #{@available_tools.size} tools from #{mcp_configs.size} MCP server(s)")
          rescue StandardError => e
            @logger.error("Failed to load MCP tools: #{e.message}")
            @available_tools = []
          end
        end
      end
    rescue StandardError => e
      @logger.error("Failed to setup MCP client: #{e.message}")
      @mcp_client = nil
      @available_tools = []
    end

    def execute_chat_api(prompt, options)
      # Build messages array
      messages = build_messages(prompt, options)

      # Process chat with recursive tool handling
      process_chat_completion(messages)
    end

    def process_chat_completion(messages, depth = 0)
      # Prevent infinite recursion
      if depth > 10
        @logger.error("Maximum recursion depth reached in tool execution")
        return "Error: Maximum tool call depth exceeded"
      end

      # Build parameters
      parameters = {
        model: @model,
        messages: messages,
        temperature: @temperature
      }

      # Add tools if available
      parameters[:tools] = @mcp_client.to_openai_tools if @available_tools&.any? && @mcp_client

      # Log the request parameters
      @logger.info("Chat API Request (depth=#{depth}): #{JSON.pretty_generate(parameters)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_request",
                               api: "chat",
                               depth: depth,
                               parameters: parameters
                             })

      # Make the API call without streaming
      response = @openai_client.chat(parameters: parameters)

      # Log the response
      @logger.info("Chat API Response (depth=#{depth}): #{JSON.pretty_generate(response)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_response",
                               api: "chat",
                               depth: depth,
                               response: response
                             })

      # Extract the message from the response
      message = response.dig("choices", 0, "message")

      if message.nil?
        @logger.error("No message in response: #{response.inspect}")
        return "Error: No response from OpenAI"
      end

      # Check if there are tool calls
      if message["tool_calls"]
        # Add the assistant message with tool calls
        messages << {
          role: "assistant",
          content: nil,
          tool_calls: message["tool_calls"]
        }

        # Execute tools and collect results
        execute_and_append_tool_results(message["tool_calls"], messages)

        # Recursively process the next response
        process_chat_completion(messages, depth + 1)
      else
        # Regular text response - this is the final response
        response_text = message["content"] || ""
        messages << { role: "assistant", content: response_text }
        @conversation_messages = messages
        response_text
      end
    end

    def execute_responses_api(prompt, _options)
      # Build parameters
      parameters = {
        model: @model,
        input: prompt
      }

      # Add previous response ID for conversation continuity
      parameters[:previous_response_id] = @previous_response_id if @previous_response_id

      # Add tools if available
      if @available_tools&.any?
        # Convert tools to responses API format
        parameters[:tools] = @available_tools.map do |tool|
          {
            "type" => "function",
            "name" => tool.name,
            "description" => tool.description,
            "parameters" => tool.schema || {}
          }
        end
        @logger.info("Available tools for responses API: #{parameters[:tools].map { |t| t["name"] }.join(", ")}")
      else
        @logger.warn("No tools available for responses API")
      end

      # Log the request parameters
      @logger.info("Responses API Request Parameters: #{JSON.pretty_generate(parameters)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_request",
                               api: "responses",
                               parameters: parameters
                             })

      # Make the API call without streaming
      begin
        response = @openai_client.responses.create(parameters: parameters)
      rescue StandardError => e
        @logger.error("Responses API error: #{e.class} - #{e.message}")
        @logger.error("Request parameters: #{JSON.pretty_generate(parameters)}")

        # Log error to session JSON
        append_to_session_json({
                                 type: "openai_error",
                                 api: "responses",
                                 error: {
                                   class: e.class.to_s,
                                   message: e.message,
                                   backtrace: e.backtrace.first(5)
                                 }
                               })

        return "Error calling OpenAI responses API: #{e.message}"
      end

      # Log the full response
      @logger.info("Responses API Full Response: #{JSON.pretty_generate(response)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_response",
                               api: "responses",
                               response: response
                             })

      # Extract response details
      response_id = response["id"]

      # Store response ID for next conversation turn
      @previous_response_id = response_id if response_id

      # Handle response based on output structure
      output = response["output"]

      if output.nil?
        @logger.error("No output in response")
        return "Error: No output in OpenAI response"
      end

      # Check if output is an array (as per ruby-openai expert)
      if output.is_a?(Array) && !output.empty?
        first_output = output.first

        # Check if it's a function call
        if first_output["type"] == "function_call"
          # Tool call response - name and arguments are at top level in responses API
          tool_calls = output.map do |item|
            next unless item["type"] == "function_call" && item["name"]

            {
              "id" => item["call_id"] || item["id"] || SecureRandom.uuid,
              "function" => {
                "name" => item["name"],
                "arguments" => item["arguments"] || "{}"
              }
            }
          end.compact

          if tool_calls.empty?
            @logger.error("No valid tool calls found in response")
            return "Error: Invalid tool call format in response"
          end

          # Execute tools and continue
          execute_tools_and_continue(tool_calls, prompt)
        elsif first_output["content"]
          # Text response - extract text from content array
          content_items = first_output["content"]
          if content_items.is_a?(Array)
            text_content = content_items.find { |item| item["text"] }
            text_content ? text_content["text"] : ""
          else
            ""
          end
        else
          @logger.error("Unknown output structure: #{first_output.inspect}")
          "Error: Unknown response structure"
        end
      else
        @logger.error("Unexpected output format: #{output.inspect}")
        "Error: Unexpected response format"
      end
    end

    def build_messages(prompt, options)
      messages = []

      # Add system prompt if provided
      system_prompt = options[:system_prompt] || @prompt
      if system_prompt && @conversation_messages.empty?
        messages << { role: "system", content: system_prompt }
      elsif !@conversation_messages.empty?
        # Use existing conversation
        messages = @conversation_messages.dup
      end

      # Add user message
      messages << { role: "user", content: prompt }

      messages
    end

    def execute_and_append_tool_results(tool_calls, messages)
      # Log tool calls
      @logger.info("Executing tool calls: #{JSON.pretty_generate(tool_calls)}")

      # Append to session JSON
      append_to_session_json({
                               type: "tool_calls",
                               api: "chat",
                               tool_calls: tool_calls
                             })

      # Execute tool calls in parallel threads
      threads = tool_calls.map do |tool_call|
        Thread.new do
          tool_name = tool_call.dig("function", "name")
          tool_args_str = tool_call.dig("function", "arguments")

          begin
            # Parse arguments
            tool_args = tool_args_str.is_a?(String) ? JSON.parse(tool_args_str) : tool_args_str

            # Log tool execution
            @logger.info("Executing tool: #{tool_name} with args: #{JSON.pretty_generate(tool_args)}")

            # Execute tool via MCP
            result = @mcp_client.call_tool(tool_name, tool_args)

            # Log result
            @logger.info("Tool result for #{tool_name}: #{result}")

            # Append to session JSON
            append_to_session_json({
                                     type: "tool_execution",
                                     tool_name: tool_name,
                                     arguments: tool_args,
                                     result: result.to_s
                                   })

            # Return success result
            {
              success: true,
              tool_call_id: tool_call["id"],
              role: "tool",
              name: tool_name,
              content: result.to_s
            }
          rescue StandardError => e
            @logger.error("Tool execution failed for #{tool_name}: #{e.message}")
            @logger.error(e.backtrace.join("\n"))

            # Append error to session JSON
            append_to_session_json({
                                     type: "tool_error",
                                     tool_name: tool_name,
                                     arguments: tool_args,
                                     error: {
                                       class: e.class.to_s,
                                       message: e.message,
                                       backtrace: e.backtrace.first(5)
                                     }
                                   })

            # Return error result
            {
              success: false,
              tool_call_id: tool_call["id"],
              role: "tool",
              name: tool_name,
              content: "Error: #{e.message}"
            }
          end
        end
      end

      # Collect results from all threads
      tool_results = threads.map(&:value)

      # Add all tool results to messages
      tool_results.each do |result|
        messages << {
          tool_call_id: result[:tool_call_id],
          role: result[:role],
          name: result[:name],
          content: result[:content]
        }
      end
    end

    def execute_tools_and_continue(tool_calls, original_prompt)
      # Log tool calls
      @logger.info("Responses API - Handling tool calls: #{JSON.pretty_generate(tool_calls)}")

      # Append to session JSON
      append_to_session_json({
                               type: "tool_calls",
                               api: "responses",
                               tool_calls: tool_calls
                             })

      # Execute tools via MCP
      tool_outputs = []

      tool_calls.each do |tool_call|
        tool_name = tool_call.dig("function", "name")
        tool_args_str = tool_call.dig("function", "arguments")

        begin
          # Parse arguments
          tool_args = JSON.parse(tool_args_str)

          # Log tool execution
          @logger.info("Responses API - Executing tool: #{tool_name} with args: #{JSON.pretty_generate(tool_args)}")

          # Execute tool via MCP
          result = @mcp_client.call_tool(tool_name, tool_args)

          # Log result
          @logger.info("Responses API - Tool result for #{tool_name}: #{result}")

          # Append to session JSON
          append_to_session_json({
                                   type: "tool_execution",
                                   api: "responses",
                                   tool_name: tool_name,
                                   arguments: tool_args,
                                   result: result.to_s
                                 })

          tool_outputs << "Tool: #{tool_name}\nResult: #{result}"
        rescue StandardError => e
          @logger.error("Responses API - Tool execution failed for #{tool_name}: #{e.message}")
          @logger.error(e.backtrace.join("\n"))

          # Append error to session JSON
          append_to_session_json({
                                   type: "tool_error",
                                   api: "responses",
                                   tool_name: tool_name,
                                   arguments: tool_args_str,
                                   error: {
                                     class: e.class.to_s,
                                     message: e.message,
                                     backtrace: e.backtrace.first(5)
                                   }
                                 })

          tool_outputs << "Tool: #{tool_name}\nError: #{e.message}"
        end
      end

      # Format the combined prompt with tool results
      combined_prompt = "#{original_prompt}\n\nTool execution results:\n#{tool_outputs.join("\n\n")}\n\nBased on these tool results, please provide your response."

      @logger.info("Responses API - Making follow-up call with tool results")
      @logger.info("Combined prompt: #{combined_prompt}")

      # Make another responses API call with the tool results
      execute_responses_api(combined_prompt, {})
    end

    def calculate_cost(_result)
      # Simplified cost calculation
      # In reality, we'd need to track token usage
      "$0.00"
    end

    def setup_logging
      # Use session path from environment (required)
      @session_path = SessionPath.from_env
      SessionPath.ensure_directory(@session_path)

      # Create logger with session.log filename
      log_filename = "session.log"
      log_path = File.join(@session_path, log_filename)
      @logger = Logger.new(log_path)
      @logger.level = Logger::INFO

      # Custom formatter for better readability
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end

      return unless @instance_name

      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info("Started OpenAI executor for instance: #{instance_info}")
    end

    def log_request(prompt)
      caller_info = @calling_instance
      caller_info += " (#{@calling_instance_id})" if @calling_instance_id
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info("#{caller_info} -> #{instance_info}: \n---\n#{prompt}\n---")

      # Build event hash for JSON logging
      event = {
        type: "request",
        from_instance: @calling_instance,
        from_instance_id: @calling_instance_id,
        to_instance: @instance_name,
        to_instance_id: @instance_id,
        prompt: prompt,
        timestamp: Time.now.iso8601
      }

      append_to_session_json(event)
    end

    def log_response(response)
      caller_info = @calling_instance
      caller_info += " (#{@calling_instance_id})" if @calling_instance_id
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info(
        "(#{response["total_cost"]} - #{response["duration_ms"]}ms) #{instance_info} -> #{caller_info}: \n---\n#{response["result"]}\n---"
      )
    end

    def log_streaming_content(content)
      # Log streaming content similar to ClaudeCodeExecutor
      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.debug("#{instance_info} streaming: #{content}")
    end

    def append_to_session_json(event)
      json_filename = "session.log.json"
      json_path = File.join(@session_path, json_filename)

      # Use file locking to ensure thread-safe writes
      File.open(json_path, File::WRONLY | File::APPEND | File::CREAT) do |file|
        file.flock(File::LOCK_EX)

        # Create entry with metadata
        entry = {
          instance: @instance_name,
          instance_id: @instance_id,
          calling_instance: @calling_instance,
          calling_instance_id: @calling_instance_id,
          timestamp: Time.now.iso8601,
          event: event
        }

        # Write as single line JSON (JSONL format)
        file.puts(entry.to_json)

        file.flock(File::LOCK_UN)
      end
    rescue StandardError => e
      @logger.error("Failed to append to session JSON: #{e.message}")
      raise
    end

    class ExecutionError < StandardError; end
  end
end
