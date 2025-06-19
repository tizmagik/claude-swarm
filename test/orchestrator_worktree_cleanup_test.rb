# frozen_string_literal: true

require "test_helper"
require_relative "../lib/claude_swarm/orchestrator"
require_relative "../lib/claude_swarm/configuration"
require_relative "../lib/claude_swarm/mcp_generator"

class OrchestratorWorktreeCleanupTest < Minitest::Test
  def setup
    @test_dir = File.realpath(Dir.mktmpdir)
    @repo_dir = File.join(@test_dir, "test-repo")
    setup_git_repo(@repo_dir)

    @config_file = File.join(@repo_dir, "claude-swarm.yml")
    File.write(@config_file, swarm_config)

    Dir.chdir(@repo_dir) do
      @config = ClaudeSwarm::Configuration.new(@config_file, base_dir: @repo_dir)
      @generator = ClaudeSwarm::McpGenerator.new(@config)
    end
  end

  def teardown
    # Clean up any remaining worktrees
    Dir.glob(File.join(@repo_dir, ".worktrees", "*")).each do |worktree|
      system("git", "-C", @repo_dir, "worktree", "remove", "--force", worktree,
             out: File::NULL, err: File::NULL)
    end
    FileUtils.rm_rf(@test_dir)
  end

  def test_orchestrator_skips_cleanup_with_uncommitted_changes
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config, @generator,
        worktree: "test-uncommitted"
      )

      # Mock system to simulate Claude execution and make changes
      orchestrator.stub :system, lambda { |*_args|
        # Find the worktree path
        worktree_path = File.join(@repo_dir, ".worktrees", "test-uncommitted")

        # Make uncommitted changes in the worktree
        File.write(File.join(worktree_path, "uncommitted.txt"), "changes") if File.exist?(worktree_path)

        true
      } do
        output = capture_io { orchestrator.start }.join

        # Check that cleanup warning was shown
        assert_match(/has uncommitted changes, skipping cleanup/, output)
      end

      # Verify worktree still exists
      worktree_path = File.join(@repo_dir, ".worktrees", "test-uncommitted")

      assert_path_exists worktree_path, "Worktree should not be deleted with uncommitted changes"
    end
  end

  def test_orchestrator_skips_cleanup_with_unpushed_commits
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config, @generator,
        worktree: "test-unpushed"
      )

      # Mock system to simulate Claude execution and make commits
      orchestrator.stub :system, lambda { |*_args|
        # Find the worktree path
        worktree_path = File.join(@repo_dir, ".worktrees", "test-unpushed")

        # Make a commit in the worktree
        if File.exist?(worktree_path)
          Dir.chdir(worktree_path) do
            File.write("new_feature.txt", "feature content")
            system("git", "add", ".", out: File::NULL, err: File::NULL)
            system("git", "commit", "-m", "New feature", out: File::NULL, err: File::NULL)
          end
        end

        true
      } do
        output = capture_io { orchestrator.start }.join

        # Check that cleanup warning was shown
        assert_match(/has unpushed commits, skipping cleanup/, output)
      end

      # Verify worktree still exists
      worktree_path = File.join(@repo_dir, ".worktrees", "test-unpushed")

      assert_path_exists worktree_path, "Worktree should not be deleted with unpushed commits"
    end
  end

  def test_orchestrator_cleans_up_clean_worktree
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config, @generator,
        worktree: "test-clean"
      )

      orchestrator.stub :system, true do
        output = capture_io { orchestrator.start }.join

        # Should see normal cleanup message
        assert_match(/Removing worktree:.*test-clean/, output)
      end

      # Verify worktree was removed
      worktree_path = File.join(@repo_dir, ".worktrees", "test-clean")

      refute_path_exists worktree_path, "Clean worktree should be deleted"
    end
  end

  private

  def setup_git_repo(dir)
    FileUtils.mkdir_p(dir)
    Dir.chdir(dir) do
      system("git", "init", "--quiet", out: File::NULL, err: File::NULL)
      # Configure git user for GitHub Actions
      system("git", "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL, err: File::NULL)
      File.write("test.txt", "test content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", "--quiet", out: File::NULL, err: File::NULL)
    end
  end

  def swarm_config
    <<~YAML
      version: 1
      swarm:
        name: "Test Swarm"
        main: main
        instances:
          main:
            description: "Main instance"
            directory: .
            model: sonnet
            allowed_tools: [Read]
    YAML
  end
end
