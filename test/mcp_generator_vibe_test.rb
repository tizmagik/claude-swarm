# frozen_string_literal: true

require "test_helper"
require "claude_swarm/configuration"
require "claude_swarm/mcp_generator"

class McpGeneratorVibeTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def read_mcp_config(instance_name)
    generator = ClaudeSwarm::McpGenerator.new(@config)
    mcp_path = generator.mcp_config_path(instance_name)
    JSON.parse(File.read(mcp_path))
  end

  def test_instance_vibe_skips_permission_mcp
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: leader
        instances:
          leader:
            description: "Leader with vibe"
            vibe: true
            tools: [Read, Edit]
    YAML

    @config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(@config)

    Dir.chdir(@tmpdir) do
      generator.generate_all
      mcp_config = read_mcp_config("leader")

      # Should not have permissions MCP when instance has vibe: true
      refute mcp_config["mcpServers"].key?("permissions")
      assert_empty mcp_config["mcpServers"]
    end
  end

  def test_global_vibe_skips_permission_mcp
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: leader
        instances:
          leader:
            description: "Leader"
            tools: [Read, Edit]
    YAML

    @config = ClaudeSwarm::Configuration.new(@config_path)
    # Test with global vibe enabled
    generator = ClaudeSwarm::McpGenerator.new(@config, vibe: true)

    Dir.chdir(@tmpdir) do
      generator.generate_all
      mcp_config = read_mcp_config("leader")

      # Should not have permissions MCP when global vibe is true
      refute mcp_config["mcpServers"].key?("permissions")
      assert_empty mcp_config["mcpServers"]
    end
  end

  def test_mixed_vibe_instances
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: leader
        instances:
          leader:
            description: "Leader without vibe"
            tools: [Read, Edit]
            connections: [worker]
          worker:
            description: "Worker with vibe"
            vibe: true
            tools: [Bash, Write]
    YAML

    @config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(@config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Leader should have permissions MCP
      leader_config = read_mcp_config("leader")

      assert leader_config["mcpServers"].key?("permissions")

      # Worker should not have permissions MCP
      worker_config = read_mcp_config("worker")

      refute worker_config["mcpServers"].key?("permissions")
    end
  end

  def test_connection_args_include_vibe
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: leader
        instances:
          leader:
            description: "Leader"
            connections: [worker]
          worker:
            description: "Worker with vibe"
            vibe: true
    YAML

    @config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(@config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      leader_config = read_mcp_config("leader")
      worker_mcp = leader_config["mcpServers"]["worker"]

      # Worker MCP should have --vibe flag
      assert_includes worker_mcp["args"], "--vibe"
    end
  end
end
