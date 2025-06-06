# frozen_string_literal: true

require "json"
require "fileutils"
require "shellwords"
require "securerandom"
require_relative "session_path"

module ClaudeSwarm
  class McpGenerator
    def initialize(configuration, vibe: false)
      @config = configuration
      @vibe = vibe
      @session_path = nil # Will be set when needed
      @instance_ids = {} # Store instance IDs for all instances
    end

    def generate_all
      ensure_swarm_directory

      # Generate all instance IDs upfront
      @config.instances.each_key do |name|
        @instance_ids[name] = "#{name}_#{SecureRandom.hex(4)}"
      end

      @config.instances.each do |name, instance|
        generate_mcp_config(name, instance)
      end
    end

    def mcp_config_path(instance_name)
      File.join(session_path, "#{instance_name}.mcp.json")
    end

    private

    def session_path
      @session_path ||= SessionPath.from_env
    end

    def ensure_swarm_directory
      # Session directory is already created by orchestrator
      # Just ensure it exists
      SessionPath.ensure_directory(session_path)
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
        mcp_servers[connection_name] = build_instance_mcp_config(
          connection_name, connected_instance,
          calling_instance: name, calling_instance_id: @instance_ids[name]
        )
      end

      # Add permission MCP server if not in vibe mode (global or instance-specific)
      mcp_servers["permissions"] = build_permission_mcp_config(instance[:tools], instance[:disallowed_tools]) unless @vibe || instance[:vibe]

      config = {
        "instance_id" => @instance_ids[name],
        "instance_name" => name,
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

    def build_instance_mcp_config(name, instance, calling_instance:, calling_instance_id:)
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

      args.push("--description", instance[:description]) if instance[:description]

      args.push("--tools", instance[:tools].join(",")) if instance[:tools] && !instance[:tools].empty?

      args.push("--disallowed-tools", instance[:disallowed_tools].join(",")) if instance[:disallowed_tools] && !instance[:disallowed_tools].empty?

      args.push("--mcp-config-path", mcp_config_path(name))

      args.push("--calling-instance", calling_instance) if calling_instance

      args.push("--calling-instance-id", calling_instance_id) if calling_instance_id

      args.push("--instance-id", @instance_ids[name]) if @instance_ids[name]

      args.push("--vibe") if @vibe || instance[:vibe]

      {
        "type" => "stdio",
        "command" => exe_path,
        "args" => args
      }
    end

    def build_permission_mcp_config(allowed_tools, disallowed_tools)
      exe_path = "claude-swarm"

      args = ["tools-mcp"]

      # Add allowed tools if specified
      args.push("--allowed-tools", allowed_tools.join(",")) if allowed_tools && !allowed_tools.empty?

      # Add disallowed tools if specified
      args.push("--disallowed-tools", disallowed_tools.join(",")) if disallowed_tools && !disallowed_tools.empty?

      {
        "type" => "stdio",
        "command" => exe_path,
        "args" => args
      }
    end
  end
end
