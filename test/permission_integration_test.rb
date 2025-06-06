# frozen_string_literal: true

require "test_helper"
require "claude_swarm/permission_mcp_server"
require "claude_swarm/permission_tool"
require "logger"

class PermissionIntegrationTest < Minitest::Test
  def setup
    # Set up session path for tests
    @tmpdir = Dir.mktmpdir
    @session_path = File.join(@tmpdir, "test_session")
    @original_env = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path

    # Create a test logger
    @log_output = StringIO.new
    @logger = Logger.new(@log_output)

    # Create MCP server instance for pattern parsing
    @mcp_server = ClaudeSwarm::PermissionMcpServer.new

    # Reset permission tool state
    ClaudeSwarm::PermissionTool.logger = @logger
    ClaudeSwarm::PermissionTool.allowed_patterns = []
    ClaudeSwarm::PermissionTool.disallowed_patterns = []

    @permission_tool = ClaudeSwarm::PermissionTool.new
  end

  def teardown
    ClaudeSwarm::PermissionTool.logger = nil
    ClaudeSwarm::PermissionTool.allowed_patterns = nil
    ClaudeSwarm::PermissionTool.disallowed_patterns = nil

    # Clean up session path
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @original_env if @original_env
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  # Test exact tool matching
  def test_exact_tool_patterns_integration
    # Parse patterns
    tool_patterns = %w[Read Write LS]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)

    # Set allowed patterns
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test exact matches are allowed
    assert_permission_allowed("Read", {})
    assert_permission_allowed("Write", {})
    assert_permission_allowed("LS", {})

    # Test non-matches are denied
    assert_permission_denied("Edit", {})
    assert_permission_denied("Bash", { command: "ls" })
    assert_permission_denied("read", {}) # case sensitive
  end

  # Test wildcard tool patterns
  def test_wildcard_tool_patterns_integration
    tool_patterns = ["mcp__headless_browser__*", "Tool*"]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test wildcard matches
    assert_permission_allowed("mcp__headless_browser__click", {})
    assert_permission_allowed("mcp__headless_browser__screenshot", {})
    assert_permission_allowed("ToolA", {})
    assert_permission_allowed("ToolBar", {})

    # Test non-matches
    assert_permission_denied("mcp__other_server__tool", {})
    assert_permission_denied("ATool", {}) # doesn't start with Tool
  end

  # Test file tool patterns with glob
  def test_file_tool_patterns_integration
    tool_patterns = [
      "Read(~/docs/*.txt)",
      "Write(/tmp/**/*.log)",
      "Edit(**/*.rb)" # Use ** to match any directory
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test glob matches
    assert_permission_allowed("Read", { file_path: "~/docs/readme.txt" })
    assert_permission_allowed("Write", { file_path: "/tmp/logs/app.log" })
    assert_permission_allowed("Write", { file_path: "/tmp/nested/deep/error.log" })
    assert_permission_allowed("Edit", { file_path: "test.rb" })
    assert_permission_allowed("Edit", { file_path: "./lib/main.rb" })

    # Test non-matches
    assert_permission_denied("Read", { file_path: "~/docs/readme.md" }) # wrong extension
    assert_permission_denied("Read", { file_path: "~/other/readme.txt" }) # wrong directory
    assert_permission_denied("Write", { file_path: "/var/log/app.log" }) # wrong base directory
    assert_permission_denied("Edit", { file_path: "test.py" }) # wrong extension
  end

  # Test Bash patterns with regex
  def test_bash_colon_patterns_integration
    tool_patterns = [
      "Bash(ls:*)",
      "Bash(git:add:*)",
      "Bash(npm:*:*)"
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test regex matches
    assert_permission_allowed("Bash", { command: "ls -la" })
    assert_permission_allowed("Bash", { command: "ls -la /tmp" })
    assert_permission_allowed("Bash", { command: "ls /home" })
    assert_permission_allowed("Bash", { command: "git add ." })
    assert_permission_allowed("Bash", { command: "git add README.md" })
    assert_permission_allowed("Bash", { command: "npm install express" })
    assert_permission_allowed("Bash", { command: "npm run test" })

    # Test non-matches
    assert_permission_denied("Bash", { command: "rm -rf /" })
    assert_permission_denied("Bash", { command: "git commit" })
    assert_permission_denied("Bash", { command: "yarn install" })
  end

  # Test Bash patterns without colon
  def test_bash_literal_patterns_integration
    tool_patterns = [
      "Bash(find . -name *.txt)",
      "Bash(echo hello world)"
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test literal matches
    assert_permission_allowed("Bash", { command: "find . -name *.txt" })
    assert_permission_allowed("Bash", { command: "echo hello world" })

    # Test non-matches
    assert_permission_denied("Bash", { command: "find . -name test.txt" }) # literal * doesn't match specific file
    assert_permission_denied("Bash", { command: "echo goodbye world" })
  end

  # Test disallowed patterns take precedence
  def test_disallowed_precedence_integration
    # For Bash(*), we need to manually set the pattern as .* to match all commands
    allowed_patterns = [
      { tool_name: "Bash", pattern: ".*", type: :regex },
      { tool_name: "Read", pattern: nil, type: :exact }, # Read without pattern means allow all
      { tool_name: "Write", pattern: nil, type: :exact } # Write without pattern means allow all
    ]
    disallowed_patterns = @mcp_server.send(:parse_tool_patterns, [
                                             "Bash(rm:*)",
                                             "Write(/etc/*)",
                                             "Read(/secrets/*)"
                                           ])

    ClaudeSwarm::PermissionTool.allowed_patterns = allowed_patterns
    ClaudeSwarm::PermissionTool.disallowed_patterns = disallowed_patterns

    # Test allowed commands
    assert_permission_allowed("Bash", { command: "ls -la" })
    assert_permission_allowed("Bash", { command: "echo test" })
    assert_permission_allowed("Write", { file_path: "/tmp/test.txt" })
    assert_permission_allowed("Read", { file_path: "/home/user/doc.txt" })

    # Test disallowed commands (should be denied even though allowed patterns would match)
    assert_permission_denied("Bash", { command: "rm -rf /" }, "explicitly disallowed")
    assert_permission_denied("Write", { file_path: "/etc/passwd" }, "explicitly disallowed")
    assert_permission_denied("Read", { file_path: "/secrets/api_key.txt" }, "explicitly disallowed")
  end

  # Test mixed pattern types
  def test_mixed_patterns_integration
    tool_patterns = [
      "LS",                           # exact
      "Grep",                         # exact
      "mcp__*__*",                    # wildcard in tool name
      "Read(~/projects/**/*.rb)",     # glob file pattern
      "Write(**/*.log)",              # glob file pattern - match in any directory
      "Bash(docker:*)",               # regex bash pattern
      "Bash(kubectl get *)"           # literal bash pattern with escaped *
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test exact matches
    assert_permission_allowed("LS", {})
    assert_permission_allowed("Grep", {})

    # Test wildcard tool matches
    assert_permission_allowed("mcp__server__tool", {})
    assert_permission_allowed("mcp__another__function", {})

    # Test file glob matches
    assert_permission_allowed("Read", { file_path: "~/projects/app/main.rb" })
    assert_permission_allowed("Read", { file_path: "~/projects/lib/nested/util.rb" })
    assert_permission_allowed("Write", { file_path: "app.log" })
    assert_permission_allowed("Write", { file_path: "./logs/error.log" })

    # Test bash regex matches
    assert_permission_allowed("Bash", { command: "docker ps" })
    assert_permission_allowed("Bash", { command: "kubectl get *" }) # literal asterisk

    # Test non-matches
    assert_permission_denied("ls", {}) # case sensitive
    assert_permission_denied("mcp__", {}) # doesn't match pattern
    assert_permission_denied("Read", { file_path: "~/projects/app/main.py" })
    assert_permission_denied("Bash", { command: "kubectl get pods" }) # doesn't have literal *
  end

  # Test edge cases
  def test_edge_cases_integration
    # Empty patterns
    empty_patterns = @mcp_server.send(:parse_tool_patterns, [])
    ClaudeSwarm::PermissionTool.allowed_patterns = empty_patterns
    # When no patterns configured, all tools should be allowed
    assert_permission_allowed("AnyTool", {})

    # Patterns with special characters
    special_patterns = @mcp_server.send(:parse_tool_patterns, [
                                          "Tool.with.dots",
                                          "Tool$special",
                                          "Read(~/file[1-3].txt)",
                                          "Bash(echo \\$HOME)" # Escape $ for literal match
                                        ])
    ClaudeSwarm::PermissionTool.allowed_patterns = special_patterns

    assert_permission_allowed("Tool.with.dots", {})
    assert_permission_allowed("Tool$special", {})
    assert_permission_allowed("Read", { file_path: "~/file1.txt" })
    assert_permission_allowed("Read", { file_path: "~/file2.txt" })
    assert_permission_allowed("Bash", { command: "echo $HOME" })
  end

  # Test file path expansion
  def test_file_path_expansion_integration
    tool_patterns = [
      "Read(~/docs/*)",
      "Write(../logs/*)",
      "Edit(./src/**/*.js)"
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # The patterns should be expanded
    expected_patterns = parsed_patterns.map { |p| p[:pattern] }
    expected_patterns.each do |pattern|
      refute_includes pattern, "~", "Pattern should not contain ~ after expansion"
      refute_includes pattern, "..", "Pattern should not contain .. after expansion"
      refute pattern.start_with?("./"), "Pattern should not start with ./ after expansion"
    end

    # Test that expanded paths still match correctly
    assert_permission_allowed("Read", { file_path: "~/docs/test.txt" })
    assert_permission_allowed("Write", { file_path: "../logs/app.log" })
    assert_permission_allowed("Edit", { file_path: "./src/components/main.js" })
  end

  # Test tool without pattern but with input
  def test_tool_without_pattern_integration
    tool_patterns = %w[Read Bash WebFetch CustomTool]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Tools without patterns should allow any input
    assert_permission_allowed("Read", { file_path: "/any/file.txt" })
    assert_permission_allowed("Bash", { command: "any command" })
    assert_permission_allowed("WebFetch", { url: "https://any-site.com" })
    assert_permission_allowed("WebFetch", { data: "any data" }) # Any input works
    assert_permission_allowed("CustomTool", { param1: "value", param2: "another" })

    # Non-listed tools should still be denied
    assert_permission_denied("NotListed", { any: "input" })
  end

  # Test custom tools with patterns are now enforced
  def test_custom_tool_patterns_enforced
    tool_patterns = [
      "WebFetch(url:https://example.com/*)",
      "WebFetch(url:https://api.github.com/*)",
      "DatabaseQuery(query:SELECT * FROM users*)",
      "APICall(endpoint:/api/v1/*)"
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # These should be allowed (matching patterns):
    assert_permission_allowed("WebFetch", { url: "https://example.com/api/data" })
    assert_permission_allowed("WebFetch", { url: "https://api.github.com/repos" })
    assert_permission_allowed("DatabaseQuery", { query: "SELECT * FROM users WHERE id = 1" })
    assert_permission_allowed("APICall", { endpoint: "/api/v1/users" })

    # These should now be denied (non-matching patterns):
    assert_permission_denied("WebFetch", { url: "https://evil.com/data" }) # Wrong domain!
    assert_permission_denied("DatabaseQuery", { query: "DROP TABLE users" }) # Dangerous query!
    assert_permission_denied("APICall", { endpoint: "/api/v2/users" }) # Wrong API version!

    # Test that missing required fields are denied
    assert_permission_denied("WebFetch", { data: "some data" }) # No url field
    assert_permission_denied("DatabaseQuery", { table: "users" }) # No query field
    assert_permission_denied("APICall", { method: "GET" }) # No endpoint field

    # Tools not in the allowed list are still properly denied
    assert_permission_denied("WebSearch", { query: "test" })
    assert_permission_denied("CustomTool", { any: "input" })
  end

  # Test various custom tool pattern matching scenarios
  def test_custom_tool_pattern_matching_details
    tool_patterns = [
      "WebFetch(url:https://*.example.com/*)", # Subdomain wildcards
      "WebFetch(url:http://localhost:*/test)", # Port wildcards
      "DatabaseQuery(query:SELECT * FROM ?????_*)", # Single char and wildcard
      "APICall(endpoint:/api/*/users)", # Path segment wildcard
      "ProcessData(input:process_*_data)", # Generic pattern
      "CustomTool(content:test pattern with spaces)" # Pattern with spaces
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test subdomain wildcards
    assert_permission_allowed("WebFetch", { url: "https://api.example.com/data" })
    assert_permission_allowed("WebFetch", { url: "https://www.example.com/page" })
    assert_permission_denied("WebFetch", { url: "https://example.org/data" })

    # Test port wildcards
    assert_permission_allowed("WebFetch", { url: "http://localhost:3000/test" })
    assert_permission_allowed("WebFetch", { url: "http://localhost:8080/test" })
    assert_permission_denied("WebFetch", { url: "http://localhost:3000/prod" })

    # Test single character wildcards
    assert_permission_allowed("DatabaseQuery", { query: "SELECT * FROM users_table" })
    assert_permission_allowed("DatabaseQuery", { query: "SELECT * FROM posts_archive" })
    assert_permission_denied("DatabaseQuery", { query: "SELECT * FROM user_data" }) # Only 4 chars before _

    # Test path segment wildcards
    assert_permission_allowed("APICall", { endpoint: "/api/v1/users" })
    assert_permission_allowed("APICall", { endpoint: "/api/v2/users" })
    assert_permission_denied("APICall", { endpoint: "/api/v1/posts" })

    # Test generic field matching
    assert_permission_allowed("ProcessData", { input: "process_customer_data" })
    assert_permission_allowed("ProcessData", { input: "process_order_data" })
    assert_permission_denied("ProcessData", { input: "transform_data" })

    # Test exact match with spaces
    assert_permission_allowed("CustomTool", { content: "test pattern with spaces" })
    assert_permission_denied("CustomTool", { content: "test pattern without spaces" })
  end

  # Test that invalid patterns are denied
  def test_invalid_patterns_denied
    tool_patterns = [
      "WebFetch(https://example.com/*)", # No param name - invalid
      "APICall(no colons here)",           # No param syntax - invalid
      "DatabaseQuery()",                   # Empty pattern - invalid
      "CustomTool(  )"                     # Whitespace only - invalid
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # All should be denied because patterns are invalid
    assert_permission_denied("WebFetch", { url: "https://example.com/api" })
    assert_permission_denied("APICall", { endpoint: "/api/v1/users" })
    assert_permission_denied("DatabaseQuery", { query: "SELECT * FROM users" })
    assert_permission_denied("CustomTool", { any: "value" })
  end

  # Test parameter-based patterns for custom tools
  def test_parameter_based_patterns
    tool_patterns = [
      "WebFetch(url:https://example.com/*)",
      "APICall(method:POST, endpoint:/api/*/users)",
      "DatabaseQuery(query:SELECT *, table:users)",
      "ProcessData(action:transform, input:*_data)",
      "CustomTool(param1:value1, param2:*)"
    ]
    parsed_patterns = @mcp_server.send(:parse_tool_patterns, tool_patterns)
    ClaudeSwarm::PermissionTool.allowed_patterns = parsed_patterns

    # Test single parameter pattern
    assert_permission_allowed("WebFetch", { url: "https://example.com/api/data" })
    assert_permission_denied("WebFetch", { url: "https://evil.com/data" })
    assert_permission_denied("WebFetch", { data: "test" }) # Missing url parameter

    # Test multiple parameter patterns
    assert_permission_allowed("APICall", { method: "POST", endpoint: "/api/v1/users" })
    assert_permission_allowed("APICall", { method: "POST", endpoint: "/api/v2/users" })
    assert_permission_denied("APICall", { method: "GET", endpoint: "/api/v1/users" }) # Wrong method
    assert_permission_denied("APICall", { method: "POST", endpoint: "/api/v1/posts" }) # Wrong endpoint
    assert_permission_denied("APICall", { method: "POST" }) # Missing endpoint

    # Test exact value matching
    assert_permission_allowed("DatabaseQuery", { query: "SELECT *", table: "users" })
    assert_permission_denied("DatabaseQuery", { query: "DELETE *", table: "users" }) # Wrong query
    assert_permission_denied("DatabaseQuery", { query: "SELECT *", table: "posts" }) # Wrong table

    # Test wildcard in parameter values
    assert_permission_allowed("ProcessData", { action: "transform", input: "customer_data" })
    assert_permission_allowed("ProcessData", { action: "transform", input: "order_data" })
    assert_permission_denied("ProcessData", { action: "delete", input: "customer_data" }) # Wrong action
    assert_permission_denied("ProcessData", { action: "transform", input: "raw_input" }) # Doesn't match *_data

    # Test multiple wildcards
    assert_permission_allowed("CustomTool", { param1: "value1", param2: "anything" })
    assert_permission_allowed("CustomTool", { param1: "value1", param2: "12345" })
    assert_permission_denied("CustomTool", { param1: "value2", param2: "anything" }) # Wrong param1
    assert_permission_denied("CustomTool", { param1: "value1" }) # Missing param2
  end

  # Test complex real-world scenario
  def test_complex_real_world_scenario
    allowed_patterns = @mcp_server.send(:parse_tool_patterns, [
                                          "Read", # Allow all reads
                                          "Write(~/projects/**/*)", # Only write to projects
                                          "Edit(**/*.{rb,js,py})",        # Only edit code files in any directory
                                          "Bash(ls:*)",                   # List files
                                          "Bash(git:*)",                  # All git commands
                                          "Bash(npm:install:*)",          # Only npm install
                                          "Bash(rake test)",              # Specific rake command
                                          "mcp__github__*",               # All GitHub MCP tools
                                          "LS",                           # List directories
                                          "Grep"                          # Search files
                                        ])

    disallowed_patterns = @mcp_server.send(:parse_tool_patterns, [
                                             "Write(~/projects/secrets/*)", # No writing to secrets
                                             "Bash(git:push:*)",             # No git push
                                             "Read(/etc/shadow)"             # No reading shadow file
                                           ])

    ClaudeSwarm::PermissionTool.allowed_patterns = allowed_patterns
    ClaudeSwarm::PermissionTool.disallowed_patterns = disallowed_patterns

    # Test various scenarios
    assert_permission_allowed("Read", { file_path: "/any/file.txt" })
    assert_permission_allowed("Write", { file_path: "~/projects/app/main.rb" })
    assert_permission_allowed("Edit", { file_path: "test.rb" })
    assert_permission_allowed("Bash", { command: "ls -la" })
    assert_permission_allowed("Bash", { command: "git status" })
    assert_permission_allowed("Bash", { command: "git add ." })
    assert_permission_allowed("Bash", { command: "npm install express" })
    assert_permission_allowed("Bash", { command: "rake test" })
    assert_permission_allowed("mcp__github__create_issue", {})
    assert_permission_allowed("LS", {})
    assert_permission_allowed("Grep", {})

    # Test denied scenarios
    assert_permission_denied("Write", { file_path: "/etc/passwd" })
    assert_permission_denied("Write", { file_path: "~/projects/secrets/api.key" }, "explicitly disallowed")
    assert_permission_denied("Edit", { file_path: "test.txt" })
    assert_permission_denied("Bash", { command: "rm -rf /" })
    assert_permission_denied("Bash", { command: "git push origin main" }, "explicitly disallowed")
    assert_permission_denied("Bash", { command: "npm run test" })
    assert_permission_denied("Read", { file_path: "/etc/shadow" }, "explicitly disallowed")
    assert_permission_denied("Task", {})
  end

  private

  def assert_permission_allowed(tool_name, input)
    result = @permission_tool.call(tool_name: tool_name, input: input)
    parsed = JSON.parse(result)

    assert_equal "allow", parsed["behavior"],
                 "Expected #{tool_name} with input #{input.inspect} to be allowed"
  end

  def assert_permission_denied(tool_name, input, expected_message_part = nil)
    result = @permission_tool.call(tool_name: tool_name, input: input)
    parsed = JSON.parse(result)

    assert_equal "deny", parsed["behavior"],
                 "Expected #{tool_name} with input #{input.inspect} to be denied"

    return unless expected_message_part

    assert_includes parsed["message"], expected_message_part,
                    "Expected denial message to include '#{expected_message_part}', got: #{parsed["message"]}"
  end
end
