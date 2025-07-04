# frozen_string_literal: true

require "test_helper"
require_relative "../lib/claude_swarm/orchestrator"
require_relative "../lib/claude_swarm/configuration"
require_relative "../lib/claude_swarm/mcp_generator"
require "digest"

class OrchestratorWorktreeIntegrationTest < Minitest::Test
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
    FileUtils.rm_rf(@test_dir)
  end

  def test_orchestrator_creates_and_cleans_up_worktrees
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config,
        @generator,
        worktree: "test-feature",
      )

      # Start the orchestrator and capture the worktree path
      orchestrator.stub(:system, true) do
        orchestrator.start
      end

      # Get the worktree info from the manager
      worktree_manager = orchestrator.instance_variable_get(:@worktree_manager)

      assert(worktree_manager, "Worktree manager should exist")

      # Check that worktree was created
      created_worktrees = worktree_manager.created_worktrees

      assert_equal(1, created_worktrees.size, "One worktree should be created")

      worktree_path = created_worktrees.values.first

      assert(worktree_path, "Worktree path should be set")

      # After execution, worktree should be cleaned up
      refute_path_exists(worktree_path, "Worktree should be cleaned up after execution")

      # Verify the worktree name
      assert_equal("test-feature", worktree_manager.worktree_name)
    end
  end

  def test_orchestrator_with_auto_generated_worktree_name
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config,
        @generator,
        worktree: "",
      )

      worktree_name = nil

      orchestrator.stub(:system, lambda { |*_args|
        # Capture the worktree name from the manager
        worktree_name = orchestrator.instance_variable_get(:@worktree_manager).worktree_name
        true
      }) do
        orchestrator.start
      end

      # Verify worktree name was auto-generated with session ID
      assert_match(/^worktree-\d{8}_\d{6}$/, worktree_name)

      # Worktree name should have been captured
      assert(worktree_name, "Worktree name should be captured")
    end
  end

  def test_orchestrator_without_worktree_option
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config, @generator
      )

      orchestrator.stub(:system, true) do
        orchestrator.start
      end

      # Check no worktrees were created
      worktrees = Dir.glob(File.join(@test_dir, "*")).select do |f|
        File.directory?(f) && f != @repo_dir
      end

      assert_empty(worktrees, "No worktrees should be created")

      # Verify no worktree manager was created
      assert_nil(orchestrator.instance_variable_get(:@worktree_manager), "No worktree manager should exist")
    end
  end

  def test_worktree_cleanup_happens
    Dir.chdir(@repo_dir) do
      orchestrator = ClaudeSwarm::Orchestrator.new(
        @config,
        @generator,
        worktree: "cleanup-test",
      )

      cleanup_called = false

      # Stub the system call and check cleanup at exit
      orchestrator.stub(:system, lambda { |*_args|
        # After start, worktree_manager should exist
        worktree_manager = orchestrator.instance_variable_get(:@worktree_manager)
        # Mock the cleanup method
        worktree_manager&.define_singleton_method(:cleanup_worktrees) do
          cleanup_called = true
        end
        true
      }) do
        orchestrator.start
      end

      assert(cleanup_called, "Worktree cleanup should be called")
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
