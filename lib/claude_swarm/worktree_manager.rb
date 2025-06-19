# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"
require "pathname"
require "securerandom"

module ClaudeSwarm
  class WorktreeManager
    attr_reader :shared_worktree_name, :created_worktrees

    def initialize(cli_worktree_option = nil, session_id: nil)
      @cli_worktree_option = cli_worktree_option
      @session_id = session_id
      # Generate a name based on session ID if no option given, empty string, or default "worktree" from Thor
      @shared_worktree_name = if cli_worktree_option.nil? || cli_worktree_option.empty? || cli_worktree_option == "worktree"
                                generate_worktree_name
                              else
                                cli_worktree_option
                              end
      @created_worktrees = {} # Maps "repo_root:worktree_name" to worktree_path
      @instance_worktree_configs = {} # Stores per-instance worktree settings
    end

    def setup_worktrees(instances)
      # First pass: determine worktree configuration for each instance
      instances.each do |instance|
        worktree_config = determine_worktree_config(instance)
        @instance_worktree_configs[instance[:name]] = worktree_config
      end

      # Second pass: create necessary worktrees
      worktrees_to_create = collect_worktrees_to_create(instances)
      worktrees_to_create.each do |repo_root, worktree_name|
        create_worktree(repo_root, worktree_name)
      end

      # Third pass: map instance directories to worktree paths
      instances.each do |instance|
        worktree_config = @instance_worktree_configs[instance[:name]]

        if ENV["CLAUDE_SWARM_DEBUG"]
          puts "Debug [WorktreeManager]: Processing instance #{instance[:name]}"
          puts "Debug [WorktreeManager]: Worktree config: #{worktree_config.inspect}"
        end

        next if worktree_config[:skip]

        worktree_name = worktree_config[:name]
        original_dirs = instance[:directories] || [instance[:directory]]
        mapped_dirs = original_dirs.map { |dir| map_to_worktree_path(dir, worktree_name) }

        if ENV["CLAUDE_SWARM_DEBUG"]
          puts "Debug [WorktreeManager]: Original dirs: #{original_dirs.inspect}"
          puts "Debug [WorktreeManager]: Mapped dirs: #{mapped_dirs.inspect}"
        end

        if instance[:directories]
          instance[:directories] = mapped_dirs
          # Also update the single directory field for backward compatibility
          instance[:directory] = mapped_dirs.first
        else
          instance[:directory] = mapped_dirs.first
        end

        puts "Debug [WorktreeManager]: Updated instance[:directory] to: #{instance[:directory]}" if ENV["CLAUDE_SWARM_DEBUG"]
      end
    end

    def map_to_worktree_path(original_path, worktree_name)
      return original_path unless original_path

      expanded_path = File.expand_path(original_path)
      repo_root = find_git_root(expanded_path)

      if ENV["CLAUDE_SWARM_DEBUG"]
        puts "Debug [map_to_worktree_path]: Original path: #{original_path}"
        puts "Debug [map_to_worktree_path]: Expanded path: #{expanded_path}"
        puts "Debug [map_to_worktree_path]: Repo root: #{repo_root}"
      end

      return original_path unless repo_root

      # Check if we have a worktree for this repo and name
      worktree_key = "#{repo_root}:#{worktree_name}"
      worktree_path = @created_worktrees[worktree_key]

      if ENV["CLAUDE_SWARM_DEBUG"]
        puts "Debug [map_to_worktree_path]: Worktree key: #{worktree_key}"
        puts "Debug [map_to_worktree_path]: Worktree path: #{worktree_path}"
        puts "Debug [map_to_worktree_path]: Created worktrees: #{@created_worktrees.inspect}"
      end

      return original_path unless worktree_path

      # Calculate relative path from repo root
      relative_path = Pathname.new(expanded_path).relative_path_from(Pathname.new(repo_root)).to_s

      # Return the equivalent path in the worktree
      result = if relative_path == "."
                 worktree_path
               else
                 File.join(worktree_path, relative_path)
               end

      puts "Debug [map_to_worktree_path]: Result: #{result}" if ENV["CLAUDE_SWARM_DEBUG"]

      result
    end

    def cleanup_worktrees
      @created_worktrees.each do |worktree_key, worktree_path|
        repo_root = worktree_key.split(":", 2).first
        next unless File.exist?(worktree_path)

        # Check for uncommitted changes
        if has_uncommitted_changes?(worktree_path)
          puts "⚠️  Warning: Worktree has uncommitted changes, skipping cleanup: #{worktree_path}" unless ENV["CLAUDE_SWARM_PROMPT"]
          next
        end

        # Check for unpushed commits
        if has_unpushed_commits?(worktree_path)
          puts "⚠️  Warning: Worktree has unpushed commits, skipping cleanup: #{worktree_path}" unless ENV["CLAUDE_SWARM_PROMPT"]
          next
        end

        puts "Removing worktree: #{worktree_path}" unless ENV["CLAUDE_SWARM_PROMPT"]

        # Remove the worktree
        output, status = Open3.capture2e("git", "-C", repo_root, "worktree", "remove", worktree_path)
        next if status.success?

        puts "Warning: Failed to remove worktree: #{output}"
        # Try force remove
        output, status = Open3.capture2e("git", "-C", repo_root, "worktree", "remove", "--force", worktree_path)
        puts "Force remove result: #{output}" unless status.success?
      end
    rescue StandardError => e
      puts "Error during worktree cleanup: #{e.message}"
    end

    def session_metadata
      {
        enabled: true,
        shared_name: @shared_worktree_name,
        created_paths: @created_worktrees.dup,
        instance_configs: @instance_worktree_configs.dup
      }
    end

    # Deprecated method for backward compatibility
    def worktree_name
      @shared_worktree_name
    end

    private

    def generate_worktree_name
      # Use session ID if available, otherwise generate a random suffix
      if @session_id
        "worktree-#{@session_id}"
      else
        # Fallback to random suffix for tests or when session ID is not available
        random_suffix = SecureRandom.alphanumeric(5).downcase
        "worktree-#{random_suffix}"
      end
    end

    def determine_worktree_config(instance)
      # Check instance-level worktree setting
      instance_worktree = instance[:worktree]

      if instance_worktree.nil?
        # No instance-level setting, follow CLI behavior
        if @cli_worktree_option.nil?
          { skip: true }
        else
          { skip: false, name: @shared_worktree_name }
        end
      elsif instance_worktree == false
        # Explicitly disabled for this instance
        { skip: true }
      elsif instance_worktree == true
        # Use shared worktree (either from CLI or auto-generated)
        { skip: false, name: @shared_worktree_name }
      elsif instance_worktree.is_a?(String)
        # Use custom worktree name
        { skip: false, name: instance_worktree }
      else
        raise Error, "Invalid worktree configuration for instance '#{instance[:name]}': #{instance_worktree.inspect}"
      end
    end

    def collect_worktrees_to_create(instances)
      worktrees_needed = {}

      instances.each do |instance|
        worktree_config = @instance_worktree_configs[instance[:name]]
        next if worktree_config[:skip]

        worktree_name = worktree_config[:name]
        directories = instance[:directories] || [instance[:directory]]

        directories.each do |dir|
          next unless dir

          expanded_dir = File.expand_path(dir)
          repo_root = find_git_root(expanded_dir)
          next unless repo_root

          # Track unique repo_root:worktree_name combinations
          worktrees_needed[repo_root] ||= Set.new
          worktrees_needed[repo_root].add(worktree_name)
        end
      end

      # Convert to array of [repo_root, worktree_name] pairs
      result = []
      worktrees_needed.each do |repo_root, worktree_names|
        worktree_names.each do |worktree_name|
          result << [repo_root, worktree_name]
        end
      end
      result
    end

    def find_git_root(path)
      current = File.expand_path(path)

      while current != "/"
        return current if File.exist?(File.join(current, ".git"))

        current = File.dirname(current)
      end

      nil
    end

    def create_worktree(repo_root, worktree_name)
      worktree_key = "#{repo_root}:#{worktree_name}"
      # Create worktrees inside the repository in a .worktrees directory
      worktree_base_dir = File.join(repo_root, ".worktrees")
      worktree_path = File.join(worktree_base_dir, worktree_name)

      # Check if worktree already exists
      if File.exist?(worktree_path)
        puts "Using existing worktree: #{worktree_path}" unless ENV["CLAUDE_SWARM_PROMPT"]
        @created_worktrees[worktree_key] = worktree_path
        return
      end

      # Ensure .worktrees directory exists
      FileUtils.mkdir_p(worktree_base_dir)

      # Create .gitignore inside .worktrees to ignore all contents
      gitignore_path = File.join(worktree_base_dir, ".gitignore")
      File.write(gitignore_path, "# Ignore all worktree contents\n*\n") unless File.exist?(gitignore_path)

      # Get current branch
      output, status = Open3.capture2e("git", "-C", repo_root, "rev-parse", "--abbrev-ref", "HEAD")
      raise Error, "Failed to get current branch in #{repo_root}: #{output}" unless status.success?

      current_branch = output.strip

      # Create worktree with a new branch based on current branch
      branch_name = worktree_name
      puts "Creating worktree: #{worktree_path} with branch: #{branch_name}" unless ENV["CLAUDE_SWARM_PROMPT"]

      # Create worktree with a new branch
      output, status = Open3.capture2e("git", "-C", repo_root, "worktree", "add", "-b", branch_name, worktree_path, current_branch)

      # If branch already exists, try without -b flag
      if !status.success? && output.include?("already exists")
        puts "Branch #{branch_name} already exists, using existing branch" unless ENV["CLAUDE_SWARM_PROMPT"]
        output, status = Open3.capture2e("git", "-C", repo_root, "worktree", "add", worktree_path, branch_name)
      end

      raise Error, "Failed to create worktree: #{output}" unless status.success?

      @created_worktrees[worktree_key] = worktree_path
    end

    def has_uncommitted_changes?(worktree_path)
      # Check if there are any uncommitted changes (staged or unstaged)
      output, status = Open3.capture2e("git", "-C", worktree_path, "status", "--porcelain")
      return false unless status.success?

      # If output is not empty, there are changes
      !output.strip.empty?
    end

    def has_unpushed_commits?(worktree_path)
      # Get the current branch
      branch_output, branch_status = Open3.capture2e("git", "-C", worktree_path, "rev-parse", "--abbrev-ref", "HEAD")
      return false unless branch_status.success?

      current_branch = branch_output.strip

      # Check if the branch has an upstream
      _, upstream_status = Open3.capture2e("git", "-C", worktree_path, "rev-parse", "--abbrev-ref", "#{current_branch}@{upstream}")

      # If no upstream, check if there are any commits on this branch
      unless upstream_status.success?
        # Get the base branch (usually main or master)
        base_branch = find_base_branch(worktree_path)

        # If we can't find a base branch or this IS the base branch, check if there are any commits at all
        if base_branch.nil? || current_branch == base_branch
          # Check if this branch has any commits
          commits_output, commits_status = Open3.capture2e("git", "-C", worktree_path, "rev-list", "--count", "HEAD")
          return false unless commits_status.success?

          # If there's more than 0 commits and no upstream, they're unpushed
          return commits_output.strip.to_i.positive?
        end

        # Check if this branch has any commits not on the base branch
        commits_output, commits_status = Open3.capture2e("git", "-C", worktree_path, "rev-list", "HEAD", "^#{base_branch}")
        return false unless commits_status.success?

        # If there are commits, they're unpushed (no upstream set)
        return !commits_output.strip.empty?
      end

      # Check for unpushed commits
      unpushed_output, unpushed_status = Open3.capture2e("git", "-C", worktree_path, "rev-list", "HEAD", "^#{current_branch}@{upstream}")
      return false unless unpushed_status.success?

      # If output is not empty, there are unpushed commits
      !unpushed_output.strip.empty?
    end

    def find_base_branch(repo_path)
      # Try to find the base branch - check for main, master, or the default branch
      %w[main master].each do |branch|
        _, status = Open3.capture2e("git", "-C", repo_path, "rev-parse", "--verify", "refs/heads/#{branch}")
        return branch if status.success?
      end

      # Try to get the default branch from HEAD
      output, status = Open3.capture2e("git", "-C", repo_path, "symbolic-ref", "refs/remotes/origin/HEAD")
      if status.success?
        # Extract branch name from refs/remotes/origin/main
        branch_match = output.strip.match(%r{refs/remotes/origin/(.+)$})
        return branch_match[1] if branch_match
      end

      nil
    end
  end
end
