# frozen_string_literal: true

require "test_helper"
require "claude_swarm/permission_mcp_server"
require "tempfile"
require "fileutils"

class PermissionMcpServerTest < Minitest::Test
  def setup
    @original_pwd = Dir.pwd
    @temp_dir = Dir.mktmpdir
    Dir.chdir(@temp_dir)

    # Set up session path for tests
    @session_path = File.join(@temp_dir, "test_session")
    @original_env = ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil)
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    Dir.chdir(@original_pwd)
    FileUtils.remove_entry(@temp_dir)

    # Restore environment
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @original_env if @original_env
  end

  def test_initialization_with_no_tools
    server = ClaudeSwarm::PermissionMcpServer.new

    assert_instance_of ClaudeSwarm::PermissionMcpServer, server
  end

  def test_initialization_with_allowed_tools
    server = ClaudeSwarm::PermissionMcpServer.new(allowed_tools: %w[Read Write])

    assert_instance_of ClaudeSwarm::PermissionMcpServer, server
  end

  def test_initialization_with_disallowed_tools
    server = ClaudeSwarm::PermissionMcpServer.new(disallowed_tools: %w[Bash Execute])

    assert_instance_of ClaudeSwarm::PermissionMcpServer, server
  end

  def test_initialization_creates_log_directory
    ClaudeSwarm::PermissionMcpServer.new

    # Check that session directory was created
    assert_path_exists @session_path
    assert_path_exists File.join(@session_path, "permissions.log")
  end

  def test_parse_tool_patterns_with_nil
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, nil)

    assert_empty result
  end

  def test_parse_tool_patterns_with_empty_string
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, "")

    assert_empty result
  end

  def test_parse_tool_patterns_with_simple_tools
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, %w[Read Write Edit])
    expected = [
      { tool_name: "Read", pattern: nil, type: :exact },
      { tool_name: "Write", pattern: nil, type: :exact },
      { tool_name: "Edit", pattern: nil, type: :exact }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_file_tools
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Write(~/foo)", "Read(*.rb)", "Edit(../test.txt)"])
    expected = [
      { tool_name: "Write", pattern: File.expand_path("~/foo"), type: :glob },
      { tool_name: "Read", pattern: File.expand_path("*.rb"), type: :glob },
      { tool_name: "Edit", pattern: File.expand_path("../test.txt"), type: :glob }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_bash_colon_pattern
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Bash(ls:*)", "Bash(npm:install)"])
    expected = [
      { tool_name: "Bash", pattern: "ls .*", type: :regex },
      { tool_name: "Bash", pattern: "npm install", type: :regex }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_bash_no_colon
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Bash(echo hello)"])
    expected = [
      { tool_name: "Bash", pattern: "echo hello", type: :regex }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_mixed_input
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Read", "Write(~/docs/*)", "Bash(ls:-la)", "Edit"])
    expected = [
      { tool_name: "Read", pattern: nil, type: :exact },
      { tool_name: "Write", pattern: File.expand_path("~/docs/*"), type: :glob },
      { tool_name: "Bash", pattern: "ls -la", type: :regex },
      { tool_name: "Edit", pattern: nil, type: :exact }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_complex_patterns
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Write(/path/with spaces/file.txt)", "Bash(git:commit:-m:\"message\")"])
    expected = [
      { tool_name: "Write", pattern: File.expand_path("/path/with spaces/file.txt"), type: :glob },
      { tool_name: "Bash", pattern: "git commit -m \"message\"", type: :regex }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_handles_empty_items
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Read", "", "Write", "  ", "Edit"])
    expected = [
      { tool_name: "Read", pattern: nil, type: :exact },
      { tool_name: "Write", pattern: nil, type: :exact },
      { tool_name: "Edit", pattern: nil, type: :exact }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_special_characters_in_pattern
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Write(~/[a-z]+\\.rb)", "Read(file*.{rb,js})"])
    expected = [
      { tool_name: "Write", pattern: File.expand_path("~/[a-z]+\\.rb"), type: :glob },
      { tool_name: "Read", pattern: File.expand_path("file*.{rb,js}"), type: :glob }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_bash_wildcard_escaping
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Bash(git:add:*)", "Bash(ls:*.rb)", "Bash(find . -name *.txt)"])
    expected = [
      { tool_name: "Bash", pattern: "git add .*", type: :regex },
      { tool_name: "Bash", pattern: "ls .*.rb", type: :regex },
      { tool_name: "Bash", pattern: "find . -name \\*.txt", type: :regex }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_non_file_tools
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["Search(query:keyword)", "CustomTool(path:~/path)"])
    expected = [
      { tool_name: "Search", pattern: { "query" => "keyword" }, type: :params },
      { tool_name: "CustomTool", pattern: { "path" => "~/path" }, type: :params }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_wildcard_in_tool_name
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, ["mcp__headless_browser__*"])
    expected = [
      { tool_name: "mcp__headless_browser__.*", pattern: nil, type: :regex }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_with_exact_tool_name
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, %w[LS Grep TodoRead])
    expected = [
      { tool_name: "LS", pattern: nil, type: :exact },
      { tool_name: "Grep", pattern: nil, type: :exact },
      { tool_name: "TodoRead", pattern: nil, type: :exact }
    ]

    assert_equal expected, result
  end

  def test_logging_uses_environment_session_path_if_available
    session_path = File.join(ClaudeSwarm::SessionPath.swarm_home, "sessions/test+project/20240115_120000")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path

    ClaudeSwarm::PermissionMcpServer.new

    assert_path_exists session_path, "Should use environment session path for directory"
    assert_path_exists File.join(session_path, "permissions.log")
  ensure
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def test_parse_tool_patterns_with_parameter_syntax
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, [
                           "WebFetch(url:https://example.com/*)",
                           "APICall(method:POST, endpoint:/api/*)",
                           "DatabaseQuery(query:SELECT *, table:users)",
                           "CustomTool(param1:*, param2:value2, param3:test*)"
                         ])

    expected = [
      {
        tool_name: "WebFetch",
        pattern: { "url" => "https://example.com/*" },
        type: :params
      },
      {
        tool_name: "APICall",
        pattern: { "method" => "POST", "endpoint" => "/api/*" },
        type: :params
      },
      {
        tool_name: "DatabaseQuery",
        pattern: { "query" => "SELECT *", "table" => "users" },
        type: :params
      },
      {
        tool_name: "CustomTool",
        pattern: { "param1" => "*", "param2" => "value2", "param3" => "test*" },
        type: :params
      }
    ]

    assert_equal expected, result
  end

  def test_parse_tool_patterns_mixed_syntaxes
    server = ClaudeSwarm::PermissionMcpServer.new
    result = server.send(:parse_tool_patterns, [
                           "Read",
                           "Write(~/docs/*)",
                           "Bash(ls:*)",
                           "WebFetch(url:https://example.com/*)",
                           "CustomTool(simple pattern)",
                           "mcp__server__*"
                         ])

    assert_equal 6, result.length
    assert_equal({ tool_name: "Read", pattern: nil, type: :exact }, result[0])
    assert_equal({ tool_name: "Write", pattern: File.expand_path("~/docs/*"), type: :glob }, result[1])
    assert_equal({ tool_name: "Bash", pattern: "ls .*", type: :regex }, result[2])
    assert_equal({ tool_name: "WebFetch", pattern: { "url" => "https://example.com/*" }, type: :params }, result[3])
    assert_equal({ tool_name: "CustomTool", pattern: {}, type: :params }, result[4]) # No valid params parsed
    assert_equal({ tool_name: "mcp__server__.*", pattern: nil, type: :regex }, result[5])
  end
end
