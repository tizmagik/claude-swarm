# frozen_string_literal: true

require "json"
require "logger"
require "securerandom"

module ClaudeSwarm
  class OpenAIResponses
    MAX_TURNS_WITH_TOOLS = 100_000 # virtually infinite

    def initialize(openai_client:, mcp_client:, available_tools:, logger:, instance_name:, model:, temperature: 0.3)
      @openai_client = openai_client
      @mcp_client = mcp_client
      @available_tools = available_tools
      @executor = logger  # This is actually the executor, not a logger
      @instance_name = instance_name
      @model = model
      @temperature = temperature
      @previous_response_id = nil
      @system_prompt = nil
    end

    def execute(prompt, options = {})
      # For responses API, we use string input, not array
      # System prompt is handled differently
      @system_prompt = options[:system_prompt] if options[:system_prompt]
      
      # Process with recursive tool handling
      result = process_responses_api(prompt)
      
      result
    end

    def reset_session
      @previous_response_id = nil
      @system_prompt = nil
    end

    private

    def process_responses_api(input_text, depth = 0)
      # Prevent infinite recursion
      if depth > MAX_TURNS_WITH_TOOLS
        @executor.error("Maximum recursion depth reached in tool execution")
        return "Error: Maximum tool call depth exceeded"
      end

      # Build parameters with string input
      parameters = {
        model: @model,
        input: input_text
      }

      # Add system prompt on first call if provided
      if depth == 0 && @system_prompt
        # Prepend system context to the user's prompt
        parameters[:input] = "#{@system_prompt}\n\n#{input_text}"
      end

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
        @executor.info("Available tools for responses API: #{parameters[:tools].map { |t| t["name"] }.join(", ")}")
      end

      # Log the request parameters
      @executor.info("Responses API Request (depth=#{depth}): #{JSON.pretty_generate(parameters)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_request",
                               api: "responses",
                               depth: depth,
                               parameters: parameters
                             })

      # Make the API call without streaming
      begin
        response = @openai_client.responses.create(parameters: parameters)
      rescue StandardError => e
        @executor.error("Responses API error: #{e.class} - #{e.message}")
        @executor.error("Request parameters: #{JSON.pretty_generate(parameters)}")

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
      @executor.info("Responses API Full Response (depth=#{depth}): #{JSON.pretty_generate(response)}")

      # Append to session JSON
      append_to_session_json({
                               type: "openai_response",
                               api: "responses",
                               depth: depth,
                               response: response
                             })

      # Extract response details
      response_id = response["id"]

      # Store response ID for next conversation turn
      @previous_response_id = response_id if response_id

      # Handle response based on output structure
      output = response["output"]

      if output.nil?
        @executor.error("No output in response")
        return "Error: No output in OpenAI response"
      end

      # Check if output is an array (as per documentation)
      if output.is_a?(Array) && !output.empty?
        # Check if there are function calls
        function_calls = output.select { |item| item["type"] == "function_call" }
        
        if function_calls.any?
          # Execute tools and get formatted results
          tool_results_text = execute_tools_and_format_results(function_calls)
          
          # Recursively process with tool results as new input
          process_responses_api(tool_results_text, depth + 1)
        else
          # Look for text response
          text_output = output.find { |item| item["content"] }
          if text_output && text_output["content"].is_a?(Array)
            text_content = text_output["content"].find { |item| item["text"] }
            text_content ? text_content["text"] : ""
          else
            ""
          end
        end
      else
        @executor.error("Unexpected output format: #{output.inspect}")
        "Error: Unexpected response format"
      end
    end

    def execute_tools_and_format_results(function_calls)
      # Log tool calls
      @executor.info("Responses API - Handling #{function_calls.size} function calls")

      # Append to session JSON
      append_to_session_json({
                               type: "tool_calls",
                               api: "responses",
                               tool_calls: function_calls
                             })

      # Execute tools and collect results
      tool_results = []
      
      function_calls.each do |function_call|
        tool_name = function_call["name"]
        tool_args_str = function_call["arguments"]

        begin
          # Parse arguments
          tool_args = JSON.parse(tool_args_str)

          # Log tool execution
          @executor.info("Responses API - Executing tool: #{tool_name} with args: #{JSON.pretty_generate(tool_args)}")

          # Execute tool via MCP
          result = @mcp_client.call_tool(tool_name, tool_args)

          # Log result
          @executor.info("Responses API - Tool result for #{tool_name}: #{result}")

          # Append to session JSON
          append_to_session_json({
                                   type: "tool_execution",
                                   api: "responses",
                                   tool_name: tool_name,
                                   arguments: tool_args,
                                   result: result.to_s
                                 })

          # Format result for text response
          if result.is_a?(Hash) && result["isError"]
            error_msg = result.dig("content", 0, "text") || result["content"].to_s
            tool_results << "Error executing #{tool_name}: #{error_msg}"
          else
            tool_results << "Successfully executed #{tool_name}: #{result}"
          end
        rescue StandardError => e
          @executor.error("Responses API - Tool execution failed for #{tool_name}: #{e.message}")
          @executor.error(e.backtrace.join("\n"))

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

          tool_results << "Error executing #{tool_name}: #{e.message}"
        end
      end

      # Format all results as a single text string for the next API call
      results_text = tool_results.join("\n\n")
      @executor.info("Responses API - Formatted tool results: #{results_text}")
      
      results_text
    end

    def append_to_session_json(event)
      # Delegate to the executor's log method
      @executor.log(event) if @executor.respond_to?(:log)
    end
  end
end
