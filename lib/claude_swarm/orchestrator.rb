# frozen_string_literal: true

require "shellwords"
require_relative "session_path"
require_relative "process_tracker"

module ClaudeSwarm
  class Orchestrator
    def initialize(configuration, mcp_generator, vibe: false, prompt: nil, stream_logs: false, debug: false)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
      @prompt = prompt
      @stream_logs = stream_logs
      @debug = debug
    end

    def start
      unless @prompt
        puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
        puts "😎 Vibe mode ON" if @vibe
        puts
      end

      # Generate and set session path for all instances
      session_path = SessionPath.generate(working_dir: Dir.pwd)
      SessionPath.ensure_directory(session_path)

      ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
      ENV["CLAUDE_SWARM_START_DIR"] = Dir.pwd

      unless @prompt
        puts "📝 Session files will be saved to: #{session_path}/"
        puts
      end

      # Initialize process tracker
      @process_tracker = ProcessTracker.new(session_path)

      # Set up signal handlers to clean up child processes
      setup_signal_handlers

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
        puts "   Allowed tools: #{main_instance[:tools].join(", ")}" if main_instance[:tools].any?
        puts "   Disallowed tools: #{main_instance[:disallowed_tools].join(", ")}" if main_instance[:disallowed_tools]&.any?
        puts "   Connections: #{main_instance[:connections].join(", ")}" if main_instance[:connections].any?
        puts "   😎 Vibe mode ON for this instance" if main_instance[:vibe]
        puts
      end

      command = build_main_command(main_instance)
      if @debug && !@prompt
        puts "Running: #{command}"
        puts
      end

      # Start log streaming thread if in non-interactive mode with --stream-logs
      log_thread = nil
      log_thread = start_log_streaming if @prompt && @stream_logs

      # Execute the main instance - this will cascade to other instances via MCP
      Dir.chdir(main_instance[:directory]) do
        system(*command)
      end

      # Clean up log streaming thread
      if log_thread
        log_thread.terminate
        log_thread.join
      end

      # Clean up child processes
      cleanup_processes
    end

    private

    def setup_signal_handlers
      %w[INT TERM QUIT].each do |signal|
        Signal.trap(signal) do
          puts "\n🛑 Received #{signal} signal, cleaning up..."
          cleanup_processes
          exit
        end
      end
    end

    def cleanup_processes
      @process_tracker.cleanup_all
      puts "✓ Cleanup complete"
    rescue StandardError => e
      puts "⚠️  Error during cleanup: #{e.message}"
    end

    def start_log_streaming
      Thread.new do
        session_log_path = File.join(ENV.fetch("CLAUDE_SWARM_SESSION_PATH", nil), "session.log")

        # Wait for log file to be created
        sleep 0.1 until File.exist?(session_log_path)

        # Open file and seek to end
        File.open(session_log_path, "r") do |file|
          file.seek(0, IO::SEEK_END)

          loop do
            changes = file.read
            if changes
              print changes
              $stdout.flush
            else
              sleep 0.1
            end
          end
        end
      rescue StandardError
        # Silently handle errors (file might be deleted, process might end, etc.)
      end
    end

    def build_main_command(instance)
      parts = [
        "claude",
        "--model",
        instance[:model]
      ]

      if @vibe || instance[:vibe]
        parts << "--dangerously-skip-permissions"
      else
        # Add allowed tools if any
        if instance[:tools].any?
          tools_str = instance[:tools].join(",")
          parts << "--allowedTools"
          parts << tools_str
        end

        # Add disallowed tools if any
        if instance[:disallowed_tools]&.any?
          disallowed_tools_str = instance[:disallowed_tools].join(",")
          parts << "--disallowedTools"
          parts << disallowed_tools_str
        end

        # Add permission prompt tool unless in vibe mode
        parts << "--permission-prompt-tool"
        parts << "mcp__permissions__check_permission"
      end

      if instance[:prompt]
        parts << "--append-system-prompt"
        parts << instance[:prompt]
      end

      parts << "--debug" if @debug

      mcp_config_path = @generator.mcp_config_path(@config.main_instance)
      parts << "--mcp-config"
      parts << mcp_config_path

      if @prompt
        parts << "-p"
        parts << @prompt
      else
        parts << "#{instance[:prompt]}\n\nNow just say 'I am ready to start'"
      end
    end
  end
end
