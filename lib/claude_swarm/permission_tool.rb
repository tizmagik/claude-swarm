# frozen_string_literal: true

require "json"
require "fast_mcp"

module ClaudeSwarm
  class PermissionTool < FastMcp::Tool
    # Class variables to store allowed patterns and logger
    class << self
      attr_accessor :allowed_patterns, :logger
    end

    tool_name "check_permission"
    description "Check if a tool is allowed to be used based on configured patterns"

    arguments do
      required(:tool_name).filled(:string).description("The tool requesting permission")
      required(:input).value(:hash).description("The input for the tool")
    end

    def call(tool_name:, input:)
      logger = self.class.logger
      logger.info("Permission check requested for tool: #{tool_name}")
      logger.info("Tool input: #{input.inspect}")

      # Check if the tool matches any allowed pattern
      patterns = self.class.allowed_patterns || []
      logger.info("Checking against patterns: #{patterns.inspect}")

      allowed = patterns.any? do |pattern|
        match = if pattern.include?("*")
                  # Convert wildcard pattern to regex
                  regex_pattern = pattern.gsub("*", ".*")
                  tool_name.match?(/^#{regex_pattern}$/)
                else
                  # Exact match
                  tool_name == pattern
                end
        logger.info("Pattern '#{pattern}' vs '#{tool_name}': #{match}")
        match
      end

      result = if allowed
                 logger.info("ALLOWED: Tool '#{tool_name}' matches configured patterns")
                 {
                   "behavior" => "allow",
                   "updatedInput" => input
                 }
               else
                 logger.info("DENIED: Tool '#{tool_name}' does not match any configured patterns")
                 {
                   "behavior" => "deny",
                   "message" => "Tool '#{tool_name}' is not allowed by configured patterns"
                 }
               end

      # Return JSON-stringified result as per SDK docs
      response = JSON.generate(result)
      logger.info("Returning response: #{response}")
      response
    end
  end
end
