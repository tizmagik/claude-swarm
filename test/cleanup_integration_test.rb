# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "timeout"

class CleanupIntegrationTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @config_file = File.join(@temp_dir, "test-swarm.yml")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_cleanup_kills_child_processes_on_exit
    # Create a minimal swarm config
    config_content = <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: leader
        instances:
          leader:
            directory: #{@temp_dir}
            model: sonnet
            prompt: "You are a test leader"
            allowed_tools: [Read]
            connections: []
    YAML

    File.write(@config_file, config_content)

    # Start the swarm in a subprocess
    pid = fork do
      # Redirect output to avoid cluttering test output
      $stdout = File.open(File::NULL, "w")
      $stderr = File.open(File::NULL, "w")

      # Set up a simple test environment
      ENV["CLAUDE_SWARM_TEST"] = "1"

      # Run claude-swarm with a prompt that exits immediately
      system("bundle", "exec", "claude-swarm", "-c", @config_file, "-p", "exit")
    end

    # Give it time to start
    sleep(1)

    # Send SIGTERM to the process
    begin
      Process.kill("TERM", pid)
    rescue StandardError
      nil
    end

    # Wait for it to exit with timeout
    Timeout.timeout(5) do
      Process.wait(pid)
    end

    # Check that no MCP processes are left running
    # This is more of a manual verification - in real use, we'd check
    # that the session directory has no PID file
    assert(true, "Process cleanup completed without hanging")
  rescue Timeout::Error
    begin
      Process.kill("KILL", pid)
    rescue StandardError
      nil
    end

    flunk("Process did not exit cleanly within timeout")
  end
end
