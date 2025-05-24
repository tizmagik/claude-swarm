# frozen_string_literal: true

require "shellwords"

module ClaudeSwarm
  class Orchestrator
    def initialize(configuration, mcp_generator, vibe: false)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
    end

    def start
      puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
      puts "😎 Vibe mode ON" if @vibe
      puts

      # Set session timestamp for all instances to share the same log file
      session_timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      ENV["CLAUDE_SWARM_SESSION_TIMESTAMP"] = session_timestamp
      puts "📝 Session logs will be saved to: .claude-swarm/logs/session_#{session_timestamp}.log"
      puts

      # Generate all MCP configuration files
      @generator.generate_all
      puts "✓ Generated MCP configurations in .claude-swarm/"
      puts

      # Launch the main instance
      main_instance = @config.main_instance_config
      puts "🚀 Launching main instance: #{@config.main_instance}"
      puts "   Model: #{main_instance[:model]}"
      puts "   Directory: #{main_instance[:directory]}"
      puts "   Tools: #{main_instance[:tools].join(", ")}" if main_instance[:tools].any?
      puts "   Connections: #{main_instance[:connections].join(", ")}" if main_instance[:connections].any?
      puts

      command = build_main_command(main_instance)
      if ENV["DEBUG"]
        puts "Running: #{command}"
        puts
      end

      # Execute the main instance - this will cascade to other instances via MCP
      exec(command)
    end

    private

    def build_main_command(instance)
      parts = []
      parts << "cd #{Shellwords.escape(instance[:directory])} &&"
      parts << "claude"
      parts << "--model #{instance[:model]}"

      if @vibe
        parts << "--dangerously-skip-permissions"
      elsif instance[:tools].any?
        tools_str = instance[:tools].join(",")
        parts << "--allowedTools '#{tools_str}'"
      end

      parts << "--append-system-prompt #{Shellwords.escape(instance[:prompt])}" if instance[:prompt]

      mcp_config_path = @generator.mcp_config_path(@config.main_instance)
      parts << "--mcp-config #{mcp_config_path}"

      parts.join(" ")
    end
  end
end
