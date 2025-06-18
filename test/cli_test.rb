# frozen_string_literal: true

require "test_helper"
require "claude_swarm/cli"
require "tmpdir"
require "fileutils"

class CLITest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)
    @cli = ClaudeSwarm::CLI.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def write_config(filename, content)
    File.write(filename, content)
  end

  def capture_cli_output(&)
    capture_io(&)
  end

  def test_exit_on_failure
    assert_predicate ClaudeSwarm::CLI, :exit_on_failure?
  end

  def test_version_command
    output, = capture_cli_output { @cli.version }

    assert_match(/Claude Swarm \d+\.\d+\.\d+/, output)
  end

  def test_default_task_is_start
    assert_equal "start", ClaudeSwarm::CLI.default_task
  end

  def test_start_with_missing_config_file
    assert_raises(SystemExit) do
      capture_cli_output { @cli.start("nonexistent.yml") }
    end
  end

  def test_start_with_invalid_yaml
    write_config("invalid.yml", "invalid: yaml: syntax:")

    assert_raises(SystemExit) do
      capture_cli_output { @cli.start("invalid.yml") }
    end
  end

  def test_start_with_configuration_error
    write_config("bad-config.yml", <<~YAML)
      version: 2
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    out, = capture_cli_output do
      assert_raises(SystemExit) { @cli.start("bad-config.yml") }
    end

    assert_match(/Unsupported version/, out)
  end

  def test_start_with_valid_config
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    # Mock the orchestrator to prevent actual execution
    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect :start, nil

    ClaudeSwarm::Orchestrator.stub :new, orchestrator_mock do
      capture_cli_output { @cli.start("valid.yml") }
    end

    orchestrator_mock.verify
  end

  def test_start_with_options
    write_config("custom.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "custom.yml" }

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect :start, nil

    ClaudeSwarm::Orchestrator.stub :new, orchestrator_mock do
      capture_cli_output { @cli.start }
    end

    orchestrator_mock.verify
  end

  def test_start_with_prompt_option
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"

    YAML

    @cli.options = { prompt: "Test prompt for non-interactive mode" }

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect :start, nil

    generator_mock = Minitest::Mock.new

    # Verify that prompt is passed to orchestrator
    ClaudeSwarm::McpGenerator.stub :new, generator_mock do
      ClaudeSwarm::Orchestrator.stub :new, lambda { |_config, _generator, **options|
        assert_equal "Test prompt for non-interactive mode", options[:prompt]
        assert_nil options[:vibe]
        orchestrator_mock
      } do
        output, = capture_cli_output { @cli.start("valid.yml") }
        # Verify that startup message is suppressed when prompt is provided
        refute_match(/Starting Claude Swarm/, output)
      end
    end

    orchestrator_mock.verify
  end

  def test_start_without_prompt_shows_message
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = {}

    orchestrator_mock = Minitest::Mock.new
    orchestrator_mock.expect :start, nil

    ClaudeSwarm::Orchestrator.stub :new, orchestrator_mock do
      output, = capture_cli_output { @cli.start("valid.yml") }
      # Verify that startup message is shown when prompt is not provided
      assert_match(/Starting Claude Swarm from valid\.yml\.\.\./, output)
    end

    orchestrator_mock.verify
  end

  def test_mcp_serve_with_all_options
    @cli.options = {
      name: "test_instance",
      directory: "/test/dir",
      model: "opus",
      prompt: "Test prompt",
      allowed_tools: %w[Read Edit],
      mcp_config_path: "/path/to/mcp.json",
      debug: false,
      calling_instance: "parent_instance"
    }

    server_mock = Minitest::Mock.new
    server_mock.expect :start, nil

    expected_config = {
      name: "test_instance",
      directory: "/test/dir",
      directories: ["/test/dir"],
      model: "opus",
      prompt: "Test prompt",
      description: nil,
      allowed_tools: %w[Read Edit],
      disallowed_tools: [],
      connections: [],
      mcp_config_path: "/path/to/mcp.json",
      vibe: false,
      instance_id: nil,
      claude_session_id: nil
    }

    ClaudeSwarm::ClaudeMcpServer.stub :new, lambda { |config, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      assert_equal expected_config, config
      assert_equal "parent_instance", calling_instance
      server_mock
    } do
      @cli.mcp_serve
    end

    server_mock.verify
  end

  def test_mcp_serve_with_minimal_options
    @cli.options = {
      name: "minimal",
      directory: ".",
      model: "sonnet",
      calling_instance: "test_caller"
    }

    server_mock = Minitest::Mock.new
    server_mock.expect :start, nil

    expected_config = {
      name: "minimal",
      directory: ".",
      directories: ["."],
      model: "sonnet",
      prompt: nil,
      description: nil,
      allowed_tools: [],
      disallowed_tools: [],
      connections: [],
      mcp_config_path: nil,
      vibe: false,
      instance_id: nil,
      claude_session_id: nil
    }

    ClaudeSwarm::ClaudeMcpServer.stub :new, lambda { |config, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      assert_equal expected_config, config
      assert_equal "test_caller", calling_instance
      server_mock
    } do
      @cli.mcp_serve
    end

    server_mock.verify
  end

  def test_mcp_serve_error_handling
    @cli.options = {
      name: "error",
      directory: ".",
      model: "sonnet",
      debug: false,
      calling_instance: "test_caller"
    }

    ClaudeSwarm::ClaudeMcpServer.stub :new, lambda { |_, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      raise StandardError, "Test error"
    } do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.mcp_serve }
      end

      assert_match(/Error starting MCP server: Test error/, out)
      refute_match(/backtrace/, out) # Debug is false
    end
  end

  def test_mcp_serve_error_with_debug
    @cli.options = {
      name: "error",
      directory: ".",
      model: "sonnet",
      debug: true,
      calling_instance: "test_caller"
    }

    ClaudeSwarm::ClaudeMcpServer.stub :new, lambda { |_, calling_instance:, calling_instance_id: nil| # rubocop:disable Lint/UnusedBlockArgument
      raise StandardError, "Test error"
    } do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.mcp_serve }
      end

      assert_match(/Error starting MCP server: Test error/, out)
      assert_match(/cli_test\.rb/, out) # Should show backtrace
    end
  end

  def test_start_unexpected_error_without_verbose
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "valid.yml", verbose: false }

    ClaudeSwarm::Configuration.stub :new, lambda { |_, _|
      raise StandardError, "Unexpected test error"
    } do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.start }
      end

      assert_match(/Unexpected error: Unexpected test error/, out)
      refute_match(/backtrace/, out)
    end
  end

  def test_start_unexpected_error_with_verbose
    write_config("valid.yml", <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
      #{"      "}
    YAML

    @cli.options = { config: "valid.yml", verbose: true }

    ClaudeSwarm::Configuration.stub :new, lambda { |_, _|
      raise StandardError, "Unexpected test error"
    } do
      out, = capture_cli_output do
        assert_raises(SystemExit) { @cli.start }
      end

      assert_match(/Unexpected error: Unexpected test error/, out)
      assert_match(/cli_test\.rb/, out) # Should show backtrace
    end
  end

  def test_cli_help_messages
    # Skip these tests as they depend on the executable being in the PATH
    skip "Skipping executable tests"
  end

  def test_start_help
    # Skip these tests as they depend on the executable being in the PATH
    skip "Skipping executable tests"
  end

  def test_mcp_serve_help
    # Skip these tests as they depend on the executable being in the PATH
    skip "Skipping executable tests"
  end
end
