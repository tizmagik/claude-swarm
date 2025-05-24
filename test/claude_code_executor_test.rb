# frozen_string_literal: true

require "test_helper"
require "claude_swarm/claude_code_executor"

class ClaudeCodeExecutorTest < Minitest::Test
  def setup
    @executor = ClaudeSwarm::ClaudeCodeExecutor.new
  end

  def test_initialization
    assert_nil @executor.session_id
    assert_nil @executor.last_response
    assert_equal Dir.pwd, @executor.working_directory
  end

  def test_has_session
    refute_predicate @executor, :has_session?

    # Simulate setting a session ID
    @executor.instance_variable_set(:@session_id, "test-session-123")

    assert_predicate @executor, :has_session?
  end

  def test_reset_session
    # Set some values
    @executor.instance_variable_set(:@session_id, "test-session-123")
    @executor.instance_variable_set(:@last_response, { "test" => "data" })

    @executor.reset_session

    assert_nil @executor.session_id
    assert_nil @executor.last_response
  end

  def test_custom_working_directory
    custom_dir = "/tmp"
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(working_directory: custom_dir)

    assert_equal custom_dir, executor.working_directory
  end

  def test_custom_model
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(model: "opus")
    command_array = executor.send(:build_command_array, "test prompt", {})

    assert_includes command_array, "--model"
    assert_includes command_array, "opus"
  end

  def test_mcp_config
    executor = ClaudeSwarm::ClaudeCodeExecutor.new(mcp_config: "/path/to/config.json")
    command_array = executor.send(:build_command_array, "test prompt", {})

    assert_includes command_array, "--mcp-config"
    assert_includes command_array, "/path/to/config.json"
  end

  def test_build_command_with_session
    @executor.instance_variable_set(:@session_id, "test-session-123")
    command_array = @executor.send(:build_command_array, "test prompt", {})

    assert_includes command_array, "--resume"
    assert_includes command_array, "test-session-123"
    assert_includes command_array, "--output-format"
    assert_includes command_array, "json"
    assert_includes command_array, "--print"
    assert_includes command_array, "test prompt" # No escaping in array
  end

  def test_build_command_with_new_session_option
    @executor.instance_variable_set(:@session_id, "test-session-123")
    command_array = @executor.send(:build_command_array, "test prompt", { new_session: true })

    refute_includes command_array, "--resume"
  end

  def test_build_command_with_system_prompt
    command_array = @executor.send(:build_command_array, "test prompt", { system_prompt: "You are a helpful assistant" })

    assert_includes command_array, "--system-prompt"
    assert_includes command_array, "You are a helpful assistant"
  end

  def test_build_command_with_allowed_tools
    command_array = @executor.send(:build_command_array, "test prompt", { allowed_tools: %w[Read Write Edit] })

    assert_includes command_array, "--allowedTools"
    assert_includes command_array, "Read,Write,Edit"
  end

  def test_execute_error_handling
    # Mock a failed execution with a stub status object
    status_stub = Object.new
    def status_stub.success?
      false
    end

    Open3.stub :capture3, ["", "Error message", status_stub] do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ExecutionError) do
        @executor.execute("test prompt")
      end
    end
  end

  def test_execute_parse_error
    # Mock execution returning invalid JSON with a stub status object
    status_stub = Object.new
    def status_stub.success?
      true
    end

    Open3.stub :capture3, ["invalid json", "", status_stub] do
      assert_raises(ClaudeSwarm::ClaudeCodeExecutor::ParseError) do
        @executor.execute("test prompt")
      end
    end
  end
end
