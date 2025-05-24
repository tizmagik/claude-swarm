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
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
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
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      assert Dir.exist?(".claude-swarm"), "Expected .claude-swarm directory to exist in #{Dir.pwd}, contents: #{Dir.entries(".")}"
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
            connections: [backend, frontend]
            tools: [Read, Edit]
            mcps:
              - name: "test_server"
                type: "stdio"
                command: "test-cmd"
                args: ["--flag"]
          backend:
            directory: ./backend
            model: haiku
            tools: [Bash, Grep]
            prompt: "Backend developer"
          frontend:
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Read generated config
      config_file = File.join(".claude-swarm", "lead.mcp.json")

      assert_path_exists config_file

      mcp_config = JSON.parse(File.read(config_file))

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
            mcps:
              - name: "api_server"
                type: "sse"
                url: "http://localhost:3000/events"
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      config_file = File.join(".claude-swarm", "lead.mcp.json")
      mcp_config = JSON.parse(File.read(config_file))

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
    YAML

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      config_file = File.join(".claude-swarm", "lead.mcp.json")
      mcp_config = JSON.parse(File.read(config_file))

      assert_empty(mcp_config["mcpServers"])
      assert_empty(mcp_config["mcpServers"])
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
            connections: [backend]
          backend:
            connections: [database]
          database:
    YAML

    # Create required directories
    Dir.mkdir(File.join(@tmpdir, "backend"))
    Dir.mkdir(File.join(@tmpdir, "database"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      # Check backend config has database connection
      backend_config = JSON.parse(File.read(".claude-swarm/backend.mcp.json"))

      assert backend_config["mcpServers"].key?("database")

      # Check database config has no connections
      database_config = JSON.parse(File.read(".claude-swarm/database.mcp.json"))

      assert_empty(database_config["mcpServers"])
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
            connections: [worker]
          worker:
    YAML

    Dir.mkdir(File.join(@tmpdir, "worker"))

    config = ClaudeSwarm::Configuration.new(@config_path)
    generator = ClaudeSwarm::McpGenerator.new(config)

    Dir.chdir(@tmpdir) do
      generator.generate_all

      lead_config = JSON.parse(File.read(".claude-swarm/lead.mcp.json"))
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

      config_file = File.join(".claude-swarm", "lead.mcp.json")
      mcp_config = JSON.parse(File.read(config_file))

      server = mcp_config["mcpServers"]["complex_server"]
      expected_args = ["--port", "3000", "--verbose", "--config", "/path/to/config.json"]

      assert_equal expected_args, server["args"]
    end
  end
end
