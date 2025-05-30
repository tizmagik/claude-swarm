# frozen_string_literal: true

require "shellwords"

module ClaudeSwarm
  class Orchestrator
    def initialize(configuration, mcp_generator, vibe: false, prompt: nil, session_timestamp: nil)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
      @prompt = prompt
      @session_timestamp = session_timestamp || Time.now.strftime("%Y%m%d_%H%M%S")
    end

    def start
      unless @prompt
        puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
        puts "😎 Vibe mode ON" if @vibe
        puts
      end

      # Set session timestamp for all instances to share the same session directory
      ENV["CLAUDE_SWARM_SESSION_TIMESTAMP"] = @session_timestamp
      unless @prompt
        puts "📝 Session files will be saved to: .claude-swarm/sessions/#{@session_timestamp}/"
        puts
      end

      # Generate all MCP configuration files
      @generator.generate_all
      unless @prompt
        puts "✓ Generated MCP configurations in session directory"
        puts
      end

      # Launch the main instance
      main_instance = @config.main_instance_config
      unless @prompt
        puts "🚀 Launching main instance: #{@config.main_instance}"
        puts "   Model: #{main_instance[:model]}"
        puts "   Directory: #{main_instance[:directory]}"
        puts "   Tools: #{main_instance[:tools].join(", ")}" if main_instance[:tools].any?
        puts "   Connections: #{main_instance[:connections].join(", ")}" if main_instance[:connections].any?
        puts
      end

      command = build_main_command(main_instance)
      if ENV["DEBUG"] && !@prompt
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

      parts << "-p #{Shellwords.escape(@prompt)}" if @prompt

      parts.join(" ")
    end
  end
end
