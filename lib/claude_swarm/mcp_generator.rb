# frozen_string_literal: true

require "json"
require "fileutils"
require "shellwords"

module ClaudeSwarm
  class McpGenerator
    SWARM_DIR = ".claude-swarm"
    SESSIONS_SUBDIR = "sessions"

    def initialize(configuration, vibe: false, timestamp: nil)
      @config = configuration
      @vibe = vibe
      @timestamp = timestamp || Time.now.strftime("%Y%m%d_%H%M%S")
    end

    def generate_all
      ensure_swarm_directory

      @config.instances.each do |name, instance|
        generate_mcp_config(name, instance)
      end
    end

    def mcp_config_path(instance_name)
      File.join(Dir.pwd, SWARM_DIR, SESSIONS_SUBDIR, @timestamp, "#{instance_name}.mcp.json")
    end

    private

    def swarm_dir
      File.join(Dir.pwd, SWARM_DIR)
    end

    def ensure_swarm_directory
      FileUtils.mkdir_p(swarm_dir)

      # Create session directory with timestamp
      session_dir = File.join(swarm_dir, SESSIONS_SUBDIR, @timestamp)
      FileUtils.mkdir_p(session_dir)

      gitignore_path = File.join(swarm_dir, ".gitignore")
      File.write(gitignore_path, "*\n") unless File.exist?(gitignore_path)
    end

    def generate_mcp_config(name, instance)
      mcp_servers = {}

      # Add configured MCP servers
      instance[:mcps].each do |mcp|
        mcp_servers[mcp["name"]] = build_mcp_server_config(mcp)
      end

      # Add connection MCPs for other instances
      instance[:connections].each do |connection_name|
        connected_instance = @config.instances[connection_name]
        mcp_servers[connection_name] = build_instance_mcp_config(connection_name, connected_instance, calling_instance: name)
      end

      config = {
        "mcpServers" => mcp_servers
      }

      File.write(mcp_config_path(name), JSON.pretty_generate(config))
    end

    def build_mcp_server_config(mcp)
      case mcp["type"]
      when "stdio"
        {
          "type" => "stdio",
          "command" => mcp["command"],
          "args" => mcp["args"] || []
        }.tap do |config|
          config["env"] = mcp["env"] if mcp["env"]
        end
      when "sse"
        {
          "type" => "sse",
          "url" => mcp["url"]
        }
      end
    end

    def build_instance_mcp_config(name, instance, calling_instance:)
      # Get the path to the claude-swarm executable
      exe_path = "claude-swarm"

      # Build command-line arguments for Thor
      args = [
        "mcp-serve",
        "--name", name,
        "--directory", instance[:directory],
        "--model", instance[:model]
      ]

      # Add optional arguments
      args.push("--prompt", instance[:prompt]) if instance[:prompt]

      args.push("--tools", instance[:tools].join(",")) if instance[:tools] && !instance[:tools].empty?

      args.push("--mcp-config-path", mcp_config_path(name))

      args.push("--calling-instance", calling_instance) if calling_instance

      args.push("--vibe") if @vibe

      {
        "type" => "stdio",
        "command" => exe_path,
        "args" => args
      }
    end
  end
end
