# frozen_string_literal: true

require "shellwords"
require "json"
require "fileutils"
require_relative "session_path"
require_relative "process_tracker"

module ClaudeSwarm
  class Orchestrator
    RUN_DIR = File.expand_path("~/.claude-swarm/run")

    def initialize(configuration, mcp_generator, vibe: false, prompt: nil, stream_logs: false, debug: false,
                   restore_session_path: nil)
      @config = configuration
      @generator = mcp_generator
      @vibe = vibe
      @prompt = prompt
      @stream_logs = stream_logs
      @debug = debug
      @restore_session_path = restore_session_path
      @session_path = nil
    end

    def start
      if @restore_session_path
        unless @prompt
          puts "🔄 Restoring Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
          puts
        end

        # Use existing session path
        session_path = @restore_session_path
        @session_path = session_path
        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_START_DIR"] = Dir.pwd

        # Create run symlink for restored session
        create_run_symlink

        unless @prompt
          puts "📝 Using existing session: #{session_path}/"
          puts
        end

        # Initialize process tracker
        @process_tracker = ProcessTracker.new(session_path)

        # Set up signal handlers to clean up child processes
        setup_signal_handlers

        # Regenerate MCP configurations with session IDs for restoration
        @generator.generate_all
        unless @prompt
          puts "✓ Regenerated MCP configurations with session IDs"
          puts
        end
      else
        unless @prompt
          puts "🐝 Starting Claude Swarm: #{@config.swarm_name}"
          puts "😎 Vibe mode ON" if @vibe
          puts
        end

        # Generate and set session path for all instances
        session_path = SessionPath.generate(working_dir: Dir.pwd)
        SessionPath.ensure_directory(session_path)
        @session_path = session_path

        ENV["CLAUDE_SWARM_SESSION_PATH"] = session_path
        ENV["CLAUDE_SWARM_START_DIR"] = Dir.pwd

        # Create run symlink for new session
        create_run_symlink

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

        # Save swarm config path for restoration
        save_swarm_config_path(session_path)
      end

      # Launch the main instance
      main_instance = @config.main_instance_config
      unless @prompt
        puts "🚀 Launching main instance: #{@config.main_instance}"
        puts "   Model: #{main_instance[:model]}"
        if main_instance[:directories].size == 1
          puts "   Directory: #{main_instance[:directory]}"
        else
          puts "   Directories:"
          main_instance[:directories].each { |dir| puts "     - #{dir}" }
        end
        puts "   Allowed tools: #{main_instance[:allowed_tools].join(", ")}" if main_instance[:allowed_tools].any?
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

      # Clean up child processes and run symlink
      cleanup_processes
      cleanup_run_symlink
    end

    private

    def save_swarm_config_path(session_path)
      # Copy the YAML config file to the session directory
      config_copy_path = File.join(session_path, "config.yml")
      FileUtils.cp(@config.config_path, config_copy_path)

      # Save the original working directory
      start_dir_file = File.join(session_path, "start_directory")
      File.write(start_dir_file, Dir.pwd)
    end

    def setup_signal_handlers
      %w[INT TERM QUIT].each do |signal|
        Signal.trap(signal) do
          puts "\n🛑 Received #{signal} signal, cleaning up..."
          cleanup_processes
          cleanup_run_symlink
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

    def create_run_symlink
      return unless @session_path

      FileUtils.mkdir_p(RUN_DIR)

      # Session ID is the last part of the session path
      session_id = File.basename(@session_path)
      symlink_path = File.join(RUN_DIR, session_id)

      # Remove stale symlink if exists
      File.unlink(symlink_path) if File.symlink?(symlink_path)

      # Create new symlink
      File.symlink(@session_path, symlink_path)
    rescue StandardError => e
      # Don't fail the process if symlink creation fails
      puts "⚠️  Warning: Could not create run symlink: #{e.message}" unless @prompt
    end

    def cleanup_run_symlink
      return unless @session_path

      session_id = File.basename(@session_path)
      symlink_path = File.join(RUN_DIR, session_id)
      File.unlink(symlink_path) if File.symlink?(symlink_path)
    rescue StandardError
      # Ignore errors during cleanup
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

      # Add resume flag if restoring session
      if @restore_session_path
        # Look for main instance state file
        main_instance_name = @config.main_instance
        state_files = Dir.glob(File.join(@restore_session_path, "state", "*.json"))

        # Find the state file for the main instance
        state_files.each do |state_file|
          state_data = JSON.parse(File.read(state_file))
          next unless state_data["instance_name"] == main_instance_name

          claude_session_id = state_data["claude_session_id"]
          if claude_session_id
            parts << "--resume"
            parts << claude_session_id
          end
          break
        end
      end

      if @vibe || instance[:vibe]
        parts << "--dangerously-skip-permissions"
      else
        # Build allowed tools list including MCP connections
        allowed_tools = instance[:allowed_tools].dup

        # Add mcp__instance_name for each connection
        instance[:connections].each do |connection_name|
          allowed_tools << "mcp__#{connection_name}"
        end

        # Add allowed tools if any
        if allowed_tools.any?
          tools_str = allowed_tools.join(",")
          parts << "--allowedTools"
          parts << tools_str
        end

        # Add disallowed tools if any
        if instance[:disallowed_tools]&.any?
          disallowed_tools_str = instance[:disallowed_tools].join(",")
          parts << "--disallowedTools"
          parts << disallowed_tools_str
        end
      end

      if instance[:prompt]
        parts << "--append-system-prompt"
        parts << instance[:prompt]
      end

      parts << "--debug" if @debug

      # Add additional directories with --add-dir
      if instance[:directories].size > 1
        instance[:directories][1..].each do |additional_dir|
          parts << "--add-dir"
          parts << additional_dir
        end
      end

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
