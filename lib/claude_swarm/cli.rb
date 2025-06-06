# frozen_string_literal: true

require "thor"
require_relative "configuration"
require_relative "mcp_generator"
require_relative "orchestrator"
require_relative "claude_mcp_server"
require_relative "permission_mcp_server"

module ClaudeSwarm
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "start [CONFIG_FILE]", "Start a Claude Swarm from configuration file"
    method_option :config, aliases: "-c", type: :string, default: "claude-swarm.yml",
                           desc: "Path to configuration file"
    method_option :vibe, type: :boolean, default: false,
                         desc: "Run with --dangerously-skip-permissions for all instances"
    method_option :prompt, aliases: "-p", type: :string,
                           desc: "Prompt to pass to the main Claude instance (non-interactive mode)"
    method_option :stream_logs, type: :boolean, default: false,
                                desc: "Stream session logs to stdout (only works with -p)"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    def start(config_file = nil)
      config_path = config_file || options[:config]
      unless File.exist?(config_path)
        error "Configuration file not found: #{config_path}"
        exit 1
      end

      say "Starting Claude Swarm from #{config_path}..." unless options[:prompt]

      # Validate stream_logs option
      if options[:stream_logs] && !options[:prompt]
        error "--stream-logs can only be used with -p/--prompt"
        exit 1
      end

      begin
        config = Configuration.new(config_path)
        generator = McpGenerator.new(config, vibe: options[:vibe])
        orchestrator = Orchestrator.new(config, generator,
                                        vibe: options[:vibe],
                                        prompt: options[:prompt],
                                        stream_logs: options[:stream_logs],
                                        debug: options[:debug])
        orchestrator.start
      rescue Error => e
        error e.message
        exit 1
      rescue StandardError => e
        error "Unexpected error: #{e.message}"
        error e.backtrace.join("\n") if options[:verbose]
        exit 1
      end
    end

    desc "mcp-serve", "Start an MCP server for a Claude instance"
    method_option :name, aliases: "-n", type: :string, required: true,
                         desc: "Instance name"
    method_option :directory, aliases: "-d", type: :string, required: true,
                              desc: "Working directory for the instance"
    method_option :model, aliases: "-m", type: :string, required: true,
                          desc: "Claude model to use (e.g., opus, sonnet)"
    method_option :prompt, aliases: "-p", type: :string,
                           desc: "System prompt for the instance"
    method_option :description, type: :string,
                                desc: "Description of the instance's role"
    method_option :tools, aliases: "-t", type: :array,
                          desc: "Allowed tools for the instance"
    method_option :disallowed_tools, type: :array,
                                     desc: "Disallowed tools for the instance"
    method_option :mcp_config_path, type: :string,
                                    desc: "Path to MCP configuration file"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    method_option :vibe, type: :boolean, default: false,
                         desc: "Run with --dangerously-skip-permissions"
    method_option :calling_instance, type: :string, required: true,
                                     desc: "Name of the instance that launched this MCP server"
    def mcp_serve
      instance_config = {
        name: options[:name],
        directory: options[:directory],
        model: options[:model],
        prompt: options[:prompt],
        description: options[:description],
        tools: options[:tools] || [],
        disallowed_tools: options[:disallowed_tools] || [],
        mcp_config_path: options[:mcp_config_path],
        vibe: options[:vibe]
      }

      begin
        server = ClaudeMcpServer.new(instance_config, calling_instance: options[:calling_instance])
        server.start
      rescue StandardError => e
        error "Error starting MCP server: #{e.message}"
        error e.backtrace.join("\n") if options[:debug]
        exit 1
      end
    end

    desc "init", "Initialize a new claude-swarm.yml configuration file"
    method_option :force, aliases: "-f", type: :boolean, default: false,
                          desc: "Overwrite existing configuration file"
    def init
      config_path = "claude-swarm.yml"

      if File.exist?(config_path) && !options[:force]
        error "Configuration file already exists: #{config_path}"
        error "Use --force to overwrite"
        exit 1
      end

      template = <<~YAML
        version: 1
        swarm:
          name: "Swarm Name"
          main: lead_developer
          instances:
            lead_developer:
              description: "Lead developer who coordinates the team and makes architectural decisions"
              directory: .
              model: sonnet
              prompt: "You are the lead developer coordinating the team"
              allowed_tools: [Read, Edit, Bash, Write]
              # connections: [frontend_dev, backend_dev]

            # Example instances (uncomment and modify as needed):

            # frontend_dev:
            #   description: "Frontend developer specializing in React and modern web technologies"
            #   directory: ./frontend
            #   model: sonnet
            #   prompt: "You specialize in frontend development with React, TypeScript, and modern web technologies"
            #   allowed_tools: [Read, Edit, Write, "Bash(npm:*)", "Bash(yarn:*)", "Bash(pnpm:*)"]

            # backend_dev:
            #   description: "Backend developer focusing on APIs, databases, and server architecture"
            #   directory: ../other-app/backend
            #   model: sonnet
            #   prompt: "You specialize in backend development, APIs, databases, and server architecture"
            #   allowed_tools: [Read, Edit, Write, Bash]

            # devops_engineer:
            #   description: "DevOps engineer managing infrastructure, CI/CD, and deployments"
            #   directory: .
            #   model: sonnet
            #   prompt: "You specialize in infrastructure, CI/CD, containerization, and deployment"
            #   allowed_tools: [Read, Edit, Write, "Bash(docker:*)", "Bash(kubectl:*)", "Bash(terraform:*)"]

            # qa_engineer:
            #   description: "QA engineer ensuring quality through comprehensive testing"
            #   directory: ./tests
            #   model: sonnet
            #   prompt: "You specialize in testing, quality assurance, and test automation"
            #   allowed_tools: [Read, Edit, Write, Bash]
      YAML

      File.write(config_path, template)
      say "Created #{config_path}", :green
      say "Edit this file to configure your swarm, then run 'claude-swarm' to start"
    end

    desc "version", "Show Claude Swarm version"
    def version
      say "Claude Swarm #{VERSION}"
    end

    desc "tools-mcp", "Start a permission management MCP server for tool access control"
    method_option :allowed_tools, aliases: "-t", type: :string,
                                  desc: "Comma-separated list of allowed tool patterns (supports wildcards)"
    method_option :disallowed_tools, type: :string,
                                     desc: "Comma-separated list of disallowed tool patterns (supports wildcards)"
    method_option :debug, type: :boolean, default: false,
                          desc: "Enable debug output"
    def tools_mcp
      server = PermissionMcpServer.new(allowed_tools: options[:allowed_tools], disallowed_tools: options[:disallowed_tools])
      server.start
    rescue StandardError => e
      error "Error starting permission MCP server: #{e.message}"
      error e.backtrace.join("\n") if options[:debug]
      exit 1
    end

    default_task :start

    private

    def error(message)
      say message, :red
    end
  end
end
