# frozen_string_literal: true

require "json"
require "fast_mcp_annotations"

module ClaudeSwarm
  class PermissionTool < FastMcp::Tool
    # Class variables to store allowed/disallowed patterns and logger
    class << self
      attr_accessor :allowed_patterns, :disallowed_patterns, :logger
    end

    # Tool categories
    FILE_TOOLS = %w[Read Write Edit].freeze
    BASH_TOOL = "Bash"

    # Response behaviors
    BEHAVIOR_ALLOW = "allow"
    BEHAVIOR_DENY = "deny"

    # File matching flags
    FILE_MATCH_FLAGS = File::FNM_DOTMATCH | File::FNM_PATHNAME | File::FNM_EXTGLOB

    tool_name "check_permission"
    description "Check if a tool is allowed to be used based on configured patterns"

    arguments do
      required(:tool_name).filled(:string).description("The tool requesting permission")
      required(:input).value(:hash).description("The input for the tool")
    end

    def call(tool_name:, input:)
      @current_tool_name = tool_name
      log_request(tool_name, input)

      result = evaluate_permission(tool_name, input)
      response = JSON.generate(result)

      log_response(response)
      response
    end

    private

    def evaluate_permission(tool_name, input)
      if explicitly_disallowed?(tool_name, input)
        deny_response(tool_name, "explicitly disallowed")
      elsif implicitly_allowed?(tool_name, input)
        allow_response(input)
      else
        deny_response(tool_name, "not allowed by configured patterns")
      end
    end

    def explicitly_disallowed?(tool_name, input)
      check_patterns(disallowed_patterns, tool_name, input, "Disallowed")
    end

    def implicitly_allowed?(tool_name, input)
      allowed_patterns.empty? || check_patterns(allowed_patterns, tool_name, input, "Allowed")
    end

    def check_patterns(patterns, tool_name, input, pattern_type)
      patterns.any? do |pattern_hash|
        match = matches_pattern?(tool_name, input, pattern_hash)
        log_pattern_check(pattern_type, pattern_hash, tool_name, input, match)
        match
      end
    end

    def matches_pattern?(tool_name, input, pattern_hash)
      return false unless tool_name_matches?(tool_name, pattern_hash)
      return true if pattern_hash[:pattern].nil?

      match_tool_specific_pattern(tool_name, input, pattern_hash)
    end

    def tool_name_matches?(tool_name, pattern_hash)
      case pattern_hash[:type]
      when :regex
        tool_name.match?(/^#{pattern_hash[:tool_name]}$/)
      else
        tool_name == pattern_hash[:tool_name]
      end
    end

    def match_tool_specific_pattern(_tool_name, input, pattern_hash)
      case pattern_hash[:tool_name]
      when BASH_TOOL
        match_bash_pattern(input, pattern_hash)
      when *FILE_TOOLS
        match_file_pattern(input, pattern_hash[:pattern])
      else
        match_custom_tool_pattern(input, pattern_hash)
      end
    end

    def match_bash_pattern(input, pattern_hash)
      command = extract_field_value(input, "command")
      return false unless command

      if pattern_hash[:type] == :regex
        command.match?(/^#{pattern_hash[:pattern]}$/)
      else
        command == pattern_hash[:pattern]
      end
    end

    def match_file_pattern(input, pattern)
      file_path = extract_field_value(input, "file_path")
      unless file_path
        log_missing_field("file_path", input)
        return false
      end

      File.fnmatch(pattern, File.expand_path(file_path), FILE_MATCH_FLAGS)
    end

    def match_custom_tool_pattern(input, pattern_hash)
      return false unless pattern_hash[:type] == :params && pattern_hash[:pattern].is_a?(Hash)
      return false if pattern_hash[:pattern].empty?

      match_parameter_patterns(input, pattern_hash[:pattern])
    end

    def match_parameter_patterns(input, param_patterns)
      param_patterns.all? do |param_name, param_pattern|
        value = extract_field_value(input, param_name.to_s)
        return false unless value

        regex_pattern = glob_to_regex(param_pattern)
        value.to_s.match?(/^#{regex_pattern}$/)
      end
    end

    def extract_field_value(input, field_name)
      input[field_name] || input[field_name.to_sym]
    end

    def glob_to_regex(pattern)
      Regexp.escape(pattern)
            .gsub('\*', ".*")
            .gsub('\?', ".")
    end

    # Response builders
    def allow_response(input)
      log_decision("ALLOWED", "matches configured patterns")
      {
        "behavior" => BEHAVIOR_ALLOW,
        "updatedInput" => input
      }
    end

    def deny_response(tool_name, reason)
      log_decision("DENIED", "is #{reason}")
      {
        "behavior" => BEHAVIOR_DENY,
        "message" => "Tool '#{tool_name}' is #{reason}"
      }
    end

    # Logging helpers
    def log_request(tool_name, input)
      logger&.info("Permission check requested for tool: #{tool_name}")
      logger&.info("Tool input: #{input.inspect}")
      logger&.info("Checking against allowed patterns: #{allowed_patterns.inspect}")
      logger&.info("Checking against disallowed patterns: #{disallowed_patterns.inspect}")
    end

    def log_response(response)
      logger&.info("Returning response: #{response}")
    end

    def log_pattern_check(pattern_type, pattern_hash, tool_name, input, match)
      logger&.info("#{pattern_type} pattern '#{pattern_hash.inspect}' vs '#{tool_name}' " \
                   "with input '#{input.inspect}': #{match}")
    end

    def log_decision(status, reason)
      logger&.info("#{status}: Tool '#{@current_tool_name}' #{reason}")
    end

    def log_missing_field(field_name, input)
      logger&.info("#{field_name} not found in input: #{input.inspect}")
    end

    # Convenience accessors
    def logger
      self.class.logger
    end

    def allowed_patterns
      self.class.allowed_patterns || []
    end

    def disallowed_patterns
      self.class.disallowed_patterns || []
    end
  end
end
