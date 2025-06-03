# frozen_string_literal: true

require "test_helper"
require "logger"

class PermissionToolTest < Minitest::Test
  def setup
    # Create a test logger that outputs to a string
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)

    ClaudeSwarm::PermissionTool.logger = @logger
    ClaudeSwarm::PermissionTool.allowed_patterns = []
    ClaudeSwarm::PermissionTool.disallowed_patterns = []

    @tool = ClaudeSwarm::PermissionTool.new
  end

  def teardown
    ClaudeSwarm::PermissionTool.logger = nil
    ClaudeSwarm::PermissionTool.allowed_patterns = nil
    ClaudeSwarm::PermissionTool.disallowed_patterns = nil
  end

  def test_allows_all_tools_when_no_patterns_configured
    result = @tool.call(tool_name: "Bash", input: { command: "ls" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]
    assert_equal({ "command" => "ls" }, parsed["updatedInput"])
  end

  def test_denies_tool_not_matching_allowed_patterns
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Read", pattern: nil, type: :exact },
      { tool_name: "Write", pattern: nil, type: :exact }
    ]

    result = @tool.call(tool_name: "Bash", input: { command: "rm -rf" })
    parsed = JSON.parse(result)

    assert_equal "deny", parsed["behavior"]
    assert_equal "Tool 'Bash' is not allowed by configured patterns", parsed["message"]
  end

  def test_hash_pattern_exact_match
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "LS", pattern: nil, type: :exact },
      { tool_name: "Grep", pattern: nil, type: :exact }
    ]

    # Should allow exact matches
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "LS", input: {}))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Grep", input: {}))["behavior"]

    # Should deny non-matching tools
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "ls", input: {}))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Read", input: {}))["behavior"]
  end

  def test_hash_pattern_regex_tool_name
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "mcp__headless_browser__.*", pattern: nil, type: :regex }
    ]

    # Should allow matching tools
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "mcp__headless_browser__click", input: {}))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "mcp__headless_browser__screenshot", input: {}))["behavior"]

    # Should deny non-matching tools
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "mcp__other_server__tool", input: {}))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Read", input: {}))["behavior"]
  end

  def test_hash_pattern_glob_file_tools
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Write", pattern: File.expand_path("~/docs/*"), type: :glob },
      { tool_name: "Read", pattern: File.expand_path("*.rb"), type: :glob }
    ]

    # Should allow matching file paths
    result = @tool.call(tool_name: "Write", input: { file_path: "~/docs/test.txt" })

    assert_equal "allow", JSON.parse(result)["behavior"]

    result = @tool.call(tool_name: "Read", input: { file_path: "test.rb" })

    assert_equal "allow", JSON.parse(result)["behavior"]

    # Should deny non-matching file paths
    result = @tool.call(tool_name: "Write", input: { file_path: "~/other/test.txt" })

    assert_equal "deny", JSON.parse(result)["behavior"]

    result = @tool.call(tool_name: "Read", input: { file_path: "test.py" })

    assert_equal "deny", JSON.parse(result)["behavior"]
  end

  def test_hash_pattern_regex_bash_commands
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "ls .*", type: :regex },
      { tool_name: "Bash", pattern: "git add .*", type: :regex }
    ]

    # Should allow matching commands
    result = @tool.call(tool_name: "Bash", input: { command: "ls -la" })

    assert_equal "allow", JSON.parse(result)["behavior"]

    result = @tool.call(tool_name: "Bash", input: { command: "git add ." })

    assert_equal "allow", JSON.parse(result)["behavior"]

    # Should deny non-matching commands
    result = @tool.call(tool_name: "Bash", input: { command: "rm -rf /" })

    assert_equal "deny", JSON.parse(result)["behavior"]

    result = @tool.call(tool_name: "Bash", input: { command: "git commit" })

    assert_equal "deny", JSON.parse(result)["behavior"]
  end

  def test_hash_pattern_bash_escaped_wildcards
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "find . -name \\*.txt", type: :regex }
    ]

    # Should match the exact command with literal asterisk
    result = @tool.call(tool_name: "Bash", input: { command: "find . -name *.txt" })

    assert_equal "allow", JSON.parse(result)["behavior"]

    # Should not match without the asterisk
    result = @tool.call(tool_name: "Bash", input: { command: "find . -name test.txt" })

    assert_equal "deny", JSON.parse(result)["behavior"]
  end

  def test_disallowed_hash_patterns_take_precedence
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: ".*", type: :regex }
    ]
    ClaudeSwarm::PermissionTool.disallowed_patterns = [
      { tool_name: "Bash", pattern: "rm .*", type: :regex }
    ]

    # Should allow non-rm commands
    result = @tool.call(tool_name: "Bash", input: { command: "ls -la" })

    assert_equal "allow", JSON.parse(result)["behavior"]

    # Should deny rm commands
    result = @tool.call(tool_name: "Bash", input: { command: "rm -rf /" })

    assert_equal "deny", JSON.parse(result)["behavior"]
  end

  def test_allows_tool_matching_exact_pattern
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: nil, type: :exact },
      { tool_name: "Read", pattern: nil, type: :exact }
    ]

    result = @tool.call(tool_name: "Bash", input: { command: "ls" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]
  end

  def test_allows_tool_matching_wildcard_pattern
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "mcp__server_name__.*", pattern: nil, type: :regex }
    ]

    result = @tool.call(tool_name: "mcp__server_name__SomeTool", input: {})
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]
  end

  def test_denies_tool_not_matching_wildcard_pattern
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "mcp__server_name__.*", pattern: nil, type: :regex }
    ]

    result = @tool.call(tool_name: "mcp__other_server__Tool", input: {})
    parsed = JSON.parse(result)

    assert_equal "deny", parsed["behavior"]
  end

  def test_disallowed_patterns_take_precedence
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash.*", pattern: nil, type: :regex }
    ]
    ClaudeSwarm::PermissionTool.disallowed_patterns = [
      { tool_name: "Bash\\(rm.*\\)", pattern: nil, type: :regex }
    ]

    # This should be allowed
    result = @tool.call(tool_name: "Bash(ls)", input: { command: "ls" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]

    # This should be denied
    result = @tool.call(tool_name: "Bash(rm -rf /)", input: { command: "rm -rf /" })
    parsed = JSON.parse(result)

    assert_equal "deny", parsed["behavior"]
    assert_equal "Tool 'Bash(rm -rf /)' is explicitly disallowed", parsed["message"]
  end

  def test_bash_pattern_with_colon_matches_space_format
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "ls.*", type: :regex }
    ]

    # Should match "Bash" with command "ls -la"
    result = @tool.call(tool_name: "Bash", input: { command: "ls -la" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]

    # Should match "Bash" with command "ls -a"
    result = @tool.call(tool_name: "Bash", input: { command: "ls -a" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]

    # Should match "Bash" with command "ls"
    result = @tool.call(tool_name: "Bash", input: { command: "ls" })
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]

    # Should not match "Bash" with command "rm -rf"
    result = @tool.call(tool_name: "Bash", input: { command: "rm -rf" })
    parsed = JSON.parse(result)

    assert_equal "deny", parsed["behavior"]
  end

  def test_multiple_bash_patterns
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "ls.*", type: :regex },
      { tool_name: "Bash", pattern: "cat.*", type: :regex },
      { tool_name: "Read", pattern: nil, type: :exact }
    ]

    # Test various ls formats
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "ls" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "ls -la" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "ls verbose" }))["behavior"]

    # Test cat formats
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "cat" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "cat file.txt" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "cat readme.md" }))["behavior"]

    # Test Read tool
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Read", input: {}))["behavior"]

    # Test denied tools
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "rm -rf" }))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Write", input: {}))["behavior"]
  end

  def test_complex_wildcard_patterns
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "npm.*", type: :regex },
      { tool_name: "Bash", pattern: "yarn.*", type: :regex },
      { tool_name: "mcp__.*__.*", pattern: nil, type: :regex }
    ]

    # npm patterns
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "npm install" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "npm run test" }))["behavior"]

    # yarn patterns
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "yarn add lodash" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "yarn install" }))["behavior"]

    # MCP patterns
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "mcp__server__tool", input: {}))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "mcp__my_server__my_tool", input: {}))["behavior"]

    # Should not match
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "mcp__", input: {}))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "git commit" }))["behavior"]
  end

  def test_empty_input_handling
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "TestTool", pattern: nil, type: :exact }
    ]

    result = @tool.call(tool_name: "TestTool", input: {})
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]
    assert_empty(parsed["updatedInput"])
  end

  def test_preserves_input_structure
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "ComplexTool", pattern: nil, type: :exact }
    ]

    complex_input = {
      "nested" => {
        "key" => "value",
        "array" => [1, 2, 3]
      },
      "flag" => true
    }

    result = @tool.call(tool_name: "ComplexTool", input: complex_input)
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"]
    assert_equal complex_input, parsed["updatedInput"]
  end

  def test_logging_output
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: nil, type: :exact }
    ]

    @tool.call(tool_name: "Bash", input: { command: "ls" })

    log_content = @log_output.string

    assert_match(/Permission check requested for tool: Bash/, log_content)
    assert_match(/ALLOWED: Tool 'Bash' matches configured patterns/, log_content)
  end

  def test_special_characters_in_patterns
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Tool.with.dots", pattern: nil, type: :exact },
      { tool_name: "Tool$special", pattern: nil, type: :exact },
      { tool_name: "Tool(with)(parens)", pattern: nil, type: :exact }
    ]

    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Tool.with.dots", input: {}))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Tool$special", input: {}))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Tool(with)(parens)", input: {}))["behavior"]

    # These should not match due to exact matching
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Tool_with_dots", input: {}))["behavior"]
  end

  def test_bash_pattern_edge_cases
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "Bash", pattern: "echo.*", type: :regex },
      { tool_name: "Bash", pattern: "ls.*", type: :regex }
    ]

    # Test commands with special characters
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "echo 'hello world'" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "ls -la | grep test" }))["behavior"]
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "echo with spaces" }))["behavior"]

    # Test that it doesn't match other commands
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "echoing" }))["behavior"] # matches echo.*
    assert_equal "allow", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "lsof" }))["behavior"] # matches ls.*
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "Bash", input: { command: "rm -rf" }))["behavior"] # doesn't match echo.* or ls.*
  end

  def test_glob_to_regex_conversion
    # Test the glob_to_regex helper method
    tool = @tool

    # Test basic wildcards
    assert_equal "hello.*world", tool.send(:glob_to_regex, "hello*world")
    assert_equal "test.txt", tool.send(:glob_to_regex, "test?txt")
    assert_equal ".*\\.rb", tool.send(:glob_to_regex, "*.rb")

    # Test special regex characters are escaped
    assert_equal "https://example\\.com/.*", tool.send(:glob_to_regex, "https://example.com/*")
    assert_equal "/api/\\[v1\\]/.*", tool.send(:glob_to_regex, "/api/[v1]/*")
    assert_equal "\\$HOME/.*", tool.send(:glob_to_regex, "$HOME/*")
    assert_equal "test\\(\\)\\{\\}", tool.send(:glob_to_regex, "test(){}")

    # Test complex patterns
    assert_equal "https://.*\\.example\\.com/.*", tool.send(:glob_to_regex, "https://*.example.com/*")
    assert_equal "SELECT\\ .*\\ FROM\\ ....._.*", tool.send(:glob_to_regex, "SELECT * FROM ?????_*")
  end

  def test_custom_tool_patterns_with_params
    # Test URL patterns with parameter syntax
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "WebFetch", pattern: { "url" => "https://example.com/*" }, type: :params }
    ]

    assert_equal "allow", JSON.parse(@tool.call(tool_name: "WebFetch", input: { url: "https://example.com/api/data" }))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "WebFetch", input: { url: "https://other.com/api/data" }))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "WebFetch", input: { data: "test" }))["behavior"] # No url field

    # Test multiple parameters
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "APICall", pattern: { "method" => "POST", "endpoint" => "/api/v1/*" }, type: :params }
    ]

    assert_equal "allow", JSON.parse(@tool.call(tool_name: "APICall", input: { method: "POST", endpoint: "/api/v1/users" }))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "APICall", input: { method: "GET", endpoint: "/api/v1/users" }))["behavior"]
    assert_equal "deny", JSON.parse(@tool.call(tool_name: "APICall", input: { method: "POST", endpoint: "/api/v2/users" }))["behavior"]

    # Test empty patterns are denied
    ClaudeSwarm::PermissionTool.allowed_patterns = [
      { tool_name: "CustomTool", pattern: {}, type: :params }
    ]

    assert_equal "deny", JSON.parse(@tool.call(tool_name: "CustomTool", input: { any: "value" }))["behavior"]
  end
end
