# frozen_string_literal: true

require "test_helper"
require "claude_swarm/configuration"
require "claude_swarm/mcp_generator"
require "tmpdir"
require "fileutils"
require "json"

class McpGeneratorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @config_path = File.join(@tmpdir, "claude-swarm.yml")
    @session_path = File.join(@tmpdir, "test_session")
    ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    ENV.delete("CLAUDE_SWARM_SESSION_PATH")
  end

  def write_config(content)
    File.write(@config_path, content)
  end

  def test_generate_all_creates_directory
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      assert Dir.exist?(@session_path), "Expected session directory to exist"
    end
  end

  def test_generate_main_instance_config
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test Swarm"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [backend, frontend]
            tools: [Read, Edit]
            mcps:
              - name: "test_server"
                type: "stdio"
                command: "test-cmd"
                args: ["--flag"]
          backend:
            description: "Backend instance"
            directory: ./backend
            model: haiku
            tools: [Bash, Grep]
            prompt: "Backend developer"
          frontend:
            description: "Frontend instance"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Read generated config
      mcp_config = read_mcp_config("lead")

      # Check mcpServers section
      assert mcp_config.key?("mcpServers")
      servers = mcp_config["mcpServers"]

      # Check backend connection
      assert servers.key?("backend")
      backend = servers["backend"]

      assert_equal "stdio", backend["type"]
      assert_equal "claude-swarm", backend["command"]

      args = backend["args"]

      assert_equal "mcp-serve", args[0]
      assert_includes args, "--name"
      assert_includes args, "backend"
      assert_includes args, "--directory"
      # Check that the directory arg is present - it may have different path formats
      dir_index = args.index("--directory")

      assert dir_index, "Should have --directory flag"
      assert args[dir_index + 1].end_with?("backend"), "Directory should end with 'backend'"
      assert_includes args, "--model"
      assert_includes args, "haiku"
      assert_includes args, "--prompt"
      assert_includes args, "Backend developer"
      assert_includes args, "--tools"
      assert_includes args, "Bash,Grep"

      # Check frontend connection
      assert servers.key?("frontend")
      frontend = servers["frontend"]

      assert_equal "stdio", frontend["type"]
      assert_equal "claude-swarm", frontend["command"]

      # Check custom MCP server
      assert servers.key?("test_server")
      test_server = servers["test_server"]

      assert_equal "stdio", test_server["type"]
      assert_equal "test-cmd", test_server["command"]
      assert_equal ["--flag"], test_server["args"]
    end
  end

  def test_sse_mcp_server
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "api_server"
                type: "sse"
                url: "http://localhost:3000/events"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      mcp_config = read_mcp_config("lead")

      api_server = mcp_config["mcpServers"]["api_server"]

      assert_equal "sse", api_server["type"]
      assert_equal "http://localhost:3000/events", api_server["url"]
      assert_nil api_server["command"]
      assert_nil api_server["args"]
    end
  end

  def test_empty_tools_and_connections
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      mcp_config = read_mcp_config("lead")

      # Should only have the permissions MCP
      assert_equal(1, mcp_config["mcpServers"].size)
      assert mcp_config["mcpServers"].key?("permissions")
    end
  end

  def test_generate_for_specific_instance
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [backend]
          backend:
            description: "Backend instance"
            connections: [database]
          database:
            description: "Database instance"
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))
    Dir.mkdir(File.join(@tmpdir, "database"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Check backend config has database connection
      backend_config = read_mcp_config("backend")

      assert backend_config["mcpServers"].key?("database")

      # Check database config has only permissions MCP
      database_config = read_mcp_config("database")

      assert_equal(1, database_config["mcpServers"].size)
      assert database_config["mcpServers"].key?("permissions")
    end
  end

  def test_mcp_config_path_in_args
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            connections: [worker]
          worker:
            description: "Worker instance"
    YAML

    Dir.mkdir(File.join(@tmpdir, "worker"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      lead_config = read_mcp_config("lead")
      worker_args = lead_config["mcpServers"]["worker"]["args"]

      mcp_path_index = worker_args.index("--mcp-config-path")

      assert mcp_path_index, "Should include --mcp-config-path flag"

      mcp_path = worker_args[mcp_path_index + 1]

      assert mcp_path.end_with?("worker.mcp.json")
      assert_path_exists mcp_path
    end
  end

  def test_preserves_mcp_args_array
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Test instance"
            mcps:
              - name: "complex_server"
                type: "stdio"
                command: "complex-cmd"
                args: ["--port", "3000", "--verbose", "--config", "/path/to/config.json"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      mcp_config = read_mcp_config("lead")

      server = mcp_config["mcpServers"]["complex_server"]
      expected_args = ["--port", "3000", "--verbose", "--config", "/path/to/config.json"]

      assert_equal expected_args, server["args"]
    end
  end

  def test_vibe_mode_no_permissions_mcp
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    # Test with vibe mode enabled
    generator = ClaudeSwarm::McpGenerator.new(config, vibe: true)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      mcp_config = read_mcp_config("lead")

      # In vibe mode, should have no MCPs (including no permissions MCP)
      assert_empty(mcp_config["mcpServers"])
    end
  end

  def test_permissions_mcp_with_tools
    write_config(<<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: lead
        instances:
          lead:
            description: "Lead instance"
            tools: [Read, Edit, "mcp__frontend__*"]
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      mcp_config = read_mcp_config("lead")

      # Should have permissions MCP with tools
      assert mcp_config["mcpServers"].key?("permissions")
      permissions_mcp = mcp_config["mcpServers"]["permissions"]

      assert_equal("claude-swarm", permissions_mcp["command"])
      assert_includes(permissions_mcp["args"], "tools-mcp")
      assert_includes(permissions_mcp["args"], "--allowed-tools")

      tools_index = permissions_mcp["args"].index("--allowed-tools") + 1

      assert_equal("Read,Edit,mcp__frontend__*", permissions_mcp["args"][tools_index])
    end
  end
end
