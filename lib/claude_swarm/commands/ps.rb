# frozen_string_literal: true

require "yaml"
require "json"
require "time"

module ClaudeSwarm
  module Commands
    class Ps
      RUN_DIR = File.expand_path("~/.claude-swarm/run")

      def execute
        unless Dir.exist?(RUN_DIR)
          puts "No active sessions"
          return
        end

        sessions = []

        # Read all symlinks in run directory
        Dir.glob("#{RUN_DIR}/*").each do |symlink|
          next unless File.symlink?(symlink)

          begin
            session_dir = File.readlink(symlink)
            # Skip if target doesn't exist (stale symlink)
            next unless Dir.exist?(session_dir)

            session_info = parse_session_info(session_dir)
            sessions << session_info if session_info
          rescue StandardError
            # Skip problematic symlinks
          end
        end

        if sessions.empty?
          puts "No active sessions"
          return
        end

        # Column widths
        col_session = 15
        col_swarm = 25
        col_cost = 12
        col_uptime = 10

        # Display header with proper spacing
        header = "#{
          "SESSION_ID".ljust(col_session)
        }  #{
          "SWARM_NAME".ljust(col_swarm)
        }  #{
          "TOTAL_COST".ljust(col_cost)
        }  #{
          "UPTIME".ljust(col_uptime)
        }  DIRECTORY"
        puts "\n⚠️  \e[3mTotal cost does not include the cost of the main instance\e[0m\n\n"
        puts header
        puts "-" * header.length

        # Display sessions sorted by start time (newest first)
        sessions.sort_by { |s| s[:start_time] }.reverse.each do |session|
          cost_str = format("$%.4f", session[:cost])
          puts "#{
            session[:id].ljust(col_session)
          }  #{
            truncate(session[:name], col_swarm).ljust(col_swarm)
          }  #{
            cost_str.ljust(col_cost)
          }  #{
            session[:uptime].ljust(col_uptime)
          }  #{session[:directory]}"
        end
      end

      private

      def parse_session_info(session_dir)
        session_id = File.basename(session_dir)

        # Load config for swarm name and main directory
        config_file = File.join(session_dir, "config.yml")
        return nil unless File.exist?(config_file)

        config = YAML.load_file(config_file)
        swarm_name = config.dig("swarm", "name") || "Unknown"
        main_instance = config.dig("swarm", "main")

        # Get all directories - handle both string and array formats
        dir_config = config.dig("swarm", "instances", main_instance, "directory")
        directories = if dir_config.is_a?(Array)
                        dir_config
                      else
                        [dir_config || "."]
                      end
        directories_str = directories.join(", ")

        # Calculate total cost from JSON log
        total_cost = calculate_total_cost(session_dir)

        # Get uptime from directory creation time
        start_time = File.stat(session_dir).ctime
        uptime = format_duration(Time.now - start_time)

        {
          id: session_id,
          name: swarm_name,
          cost: total_cost,
          uptime: uptime,
          directory: directories_str,
          start_time: start_time
        }
      rescue StandardError
        nil
      end

      def calculate_total_cost(session_dir)
        log_file = File.join(session_dir, "session.log.json")
        return 0.0 unless File.exist?(log_file)

        total = 0.0
        File.foreach(log_file) do |line|
          data = JSON.parse(line)
          total += data["event"]["total_cost_usd"] if data.dig("event", "type") == "result" && data.dig("event", "total_cost_usd")
        rescue JSON::ParserError
          next
        end
        total
      end

      def format_duration(seconds)
        if seconds < 60
          "#{seconds.to_i}s"
        elsif seconds < 3600
          "#{(seconds / 60).to_i}m"
        elsif seconds < 86_400
          "#{(seconds / 3600).to_i}h"
        else
          "#{(seconds / 86_400).to_i}d"
        end
      end

      def truncate(str, length)
        str.length > length ? "#{str[0...length - 2]}.." : str
      end
    end
  end
end
