# frozen_string_literal: true

require "test_helper"
require "claude_swarm/orchestrator"
require "claude_swarm/configuration"
require "claude_swarm/mcp_generator"
require "tmpdir"
require "fileutils"

class OrchestratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @original_env = ENV.to_h
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    # Restore original environment
    ENV.clear
    @original_env.each { |k, v| ENV[k] = v }
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def create_test_config
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            directory: ./src
            model: opus
            connections: [backend]
            tools: [Read, Edit, Bash]
            prompt: "You are the lead developer"
          backend:
            directory: ./backend
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "src"))
    Dir.mkdir(File.join(@tmpdir, "backend"))

    ClaudeSwarm::Configuration.new(@config_path)
  end

  def test_start_sets_session_timestamp
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    # Mock exec to prevent actual execution
    orchestrator.stub :exec, nil do
      capture_io do
        orchestrator.start
      end
    end

    assert ENV.fetch("CLAUDE_SWARM_SESSION_TIMESTAMP", nil)
    assert_match(/^\d{8}_\d{6}$/, ENV.fetch("CLAUDE_SWARM_SESSION_TIMESTAMP", nil))
  end

  def test_start_generates_mcp_configs
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    Dir.chdir(@tmpdir) do
      orchestrator.stub :exec, nil do
        capture_io do
          orchestrator.start
        end
      end

      assert Dir.exist?(".claude-swarm")
      assert find_mcp_file("lead"), "Expected lead.mcp.json to exist"
      assert find_mcp_file("backend"), "Expected backend.mcp.json to exist"
    end
  end

  def test_start_output_messages
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    assert_match(/🐝 Starting Claude Swarm: Test Swarm/, output)
    assert_match(%r{📝 Session files will be saved to:.*\.claude-swarm/sessions/\d{8}_\d{6}}, output)
    assert_match(/✓ Generated MCP configurations/, output)
    assert_match(/🚀 Launching main instance: lead/, output)
    assert_match(/Model: opus/, output)
    assert_match(/Directory:.*src/, output)
    assert_match(/Tools: Read, Edit, Bash/, output)
    assert_match(/Connections: backend/, output)
  end

  def test_build_main_command_with_all_options
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Parse the command to verify components
    assert_includes expected_command, "cd #{File.join(@tmpdir, "src")} &&"
    assert_includes expected_command, "claude"
    assert_includes expected_command, "--model opus"
    assert_includes expected_command, "--allowedTools 'Read,Edit,Bash'"
    assert_includes expected_command, "--append-system-prompt"
    assert_includes expected_command, "You\\ are\\ the\\ lead\\ developer"
    assert_includes expected_command, "--mcp-config"
    assert_match %r{/lead\.mcp\.json$}, expected_command
  end

  def test_build_main_command_without_tools
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # When no tools are specified and vibe is false, neither flag should be present
    refute_includes expected_command, "--dangerously-skip-permissions"
    refute_includes expected_command, "--allowedTools"
  end

  def test_build_main_command_without_prompt
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            tools: [Read]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    refute_includes expected_command, "--append-system-prompt"
  end

  def test_shellwords_escaping
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test's Swarm"
        main: lead
        instances:
          lead:
            directory: "./path with spaces"
            prompt: "You're the 'lead' developer!"
            tools: ["Bash(rm -rf *)"]
    YAML

    Dir.mkdir(File.join(@tmpdir, "path with spaces"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify proper escaping - check for the actual Shellwords escaping
    assert_includes expected_command, "path\\ with\\ spaces"
    assert_includes expected_command, "You\\'re\\ the\\ \\'lead\\'\\ developer\\!"
    assert_includes expected_command, "Bash(rm -rf *)"
  end

  def test_debug_mode_shows_command
    ENV["DEBUG"] = "true"
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    assert_match(/Running: cd.*claude.*--model/, output)
  end

  def test_empty_connections_and_tools
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Minimal"
        main: solo
        instances:
          solo:
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    # Should not show empty tools or connections
    refute_match(/Tools:/, output)
    refute_match(/Connections:/, output)
  end

  def test_absolute_path_handling
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            directory: #{@tmpdir}/absolute/path
    YAML

    FileUtils.mkdir_p(File.join(@tmpdir, "absolute", "path"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    assert_includes expected_command, "cd #{@tmpdir}/absolute/path"
  end

  def test_mcp_config_path_resolution
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Extract MCP config path from command
    mcp_match = expected_command.match(/--mcp-config\s+(\S+)/)

    assert mcp_match

    mcp_path = mcp_match[1].gsub("\\", "") # Remove escaping

    assert mcp_path.end_with?("/lead.mcp.json")
    # The file will be created when the generator runs, so we can't check it exists yet
  end

  def test_build_main_command_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Execute test task")

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify prompt is included in command
    assert_includes expected_command, "-p Execute\\ test\\ task"
  end

  def test_build_main_command_with_prompt_requiring_escaping
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Fix the 'bug' in module X")

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Verify prompt with quotes is properly escaped
    assert_includes expected_command, "-p Fix\\ the\\ \\'bug\\'\\ in\\ module\\ X"
  end

  def test_output_suppression_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Test prompt")

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    # All startup messages should be suppressed
    refute_match(/🐝 Starting Claude Swarm/, output)
    refute_match(/📝 Session logs will be saved/, output)
    refute_match(/✓ Generated MCP configurations/, output)
    refute_match(/🚀 Launching main instance/, output)
    refute_match(/Model:/, output)
    refute_match(/Directory:/, output)
    refute_match(/Tools:/, output)
    refute_match(/Connections:/, output)
  end

  def test_output_shown_without_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator)

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    # All startup messages should be shown
    assert_match(/🐝 Starting Claude Swarm/, output)
    assert_match(/📝 Session files will be saved/, output)
    assert_match(/✓ Generated MCP configurations/, output)
    assert_match(/🚀 Launching main instance/, output)
  end

  def test_debug_mode_suppressed_with_prompt
    ENV["DEBUG"] = "true"
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, prompt: "Debug test")

    output = nil
    orchestrator.stub :exec, nil do
      output = capture_io { orchestrator.start }[0]
    end

    # Debug output should also be suppressed with prompt
    refute_match(/Running:/, output)
  end

  def test_vibe_mode_with_prompt
    config = create_test_config
    generator = ClaudeSwarm::McpGenerator.new(config)
    orchestrator = ClaudeSwarm::Orchestrator.new(config, generator, vibe: true, prompt: "Vibe test")

    expected_command = nil
    orchestrator.stub :exec, ->(cmd) { expected_command = cmd } do
      Dir.chdir(@tmpdir) do
        capture_io { orchestrator.start }
      end
    end

    # Should include both vibe flag and prompt
    assert_includes expected_command, "--dangerously-skip-permissions"
    assert_includes expected_command, "-p Vibe\\ test"
  end
end
