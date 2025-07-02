# frozen_string_literal: true

require "json"
require "logger"
require "securerandom"

module ClaudeSwarm
  class OpenAIResponses
    def initialize(openai_client:, mcp_client:, available_tools:, logger:, instance_name:, model:, temperature: 0.3)
      @openai_client = openai_client
      @mcp_client = mcp_client
      @available_tools = available_tools
      @executor = logger  # This is actually the executor, not a logger
      @instance_name = instance_name
      @model = model
      @temperature = temperature
      @previous_response_id = nil
    end

    def execute(prompt, _options = {})
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
        @executor.info("Available tools for responses API: #{parameters[:tools].map { |t| t["name"] }.join(", ")}")
      else
        @executor.warn("No tools available for responses API")
      end

      # Log the request parameters
      @executor.info("Responses API Request Parameters: #{JSON.pretty_generate(parameters)}")

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
      @executor.info("Responses API Full Response: #{JSON.pretty_generate(response)}")

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
        @executor.error("No output in response")
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
            @executor.error("No valid tool calls found in response")
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
          @executor.error("Unknown output structure: #{first_output.inspect}")
          "Error: Unknown response structure"
        end
      else
        @executor.error("Unexpected output format: #{output.inspect}")
        "Error: Unexpected response format"
      end
    end

    def reset_session
      @previous_response_id = nil
    end

    private

    def execute_tools_and_continue(tool_calls, original_prompt)
      # Log tool calls
      @executor.info("Responses API - Handling tool calls: #{JSON.pretty_generate(tool_calls)}")

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

          tool_outputs << "Tool: #{tool_name}\nResult: #{result}"
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

          tool_outputs << "Tool: #{tool_name}\nError: #{e.message}"
        end
      end

      # Format the combined prompt with tool results
      combined_prompt = "#{original_prompt}\n\nTool execution results:\n#{tool_outputs.join("\n\n")}\n\nBased on these tool results, please provide your response."

      @executor.info("Responses API - Making follow-up call with tool results")
      @executor.info("Combined prompt: #{combined_prompt}")

      # Make another responses API call with the tool results
      execute(combined_prompt, {})
    end

    def append_to_session_json(event)
      # Delegate to the executor's log method
      @executor.log(event) if @executor.respond_to?(:log)
    end
  end
end
