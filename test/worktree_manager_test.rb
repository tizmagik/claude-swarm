# frozen_string_literal: true

require "test_helper"
require_relative "../lib/claude_swarm/worktree_manager"

class WorktreeManagerTest < Minitest::Test
  def setup
    @test_dir = File.realpath(Dir.mktmpdir)
    @repo_dir = File.join(@test_dir, "test-repo")
    @other_repo_dir = File.join(@test_dir, "other-repo")

    # Create test Git repositories
    setup_git_repo(@repo_dir)
    setup_git_repo(@other_repo_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_initialize_with_custom_name
    manager = ClaudeSwarm::WorktreeManager.new("feature-x")

    assert_equal "feature-x", manager.worktree_name
  end

  def test_initialize_with_auto_generated_name
    manager = ClaudeSwarm::WorktreeManager.new

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_setup_worktrees_single_repo
    manager = ClaudeSwarm::WorktreeManager.new("test-worktree")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "sub", directory: File.join(@repo_dir, "subdir") }
    ]

    manager.setup_worktrees(instances)

    # Check worktree was created
    worktree_path = File.join(@repo_dir, ".worktrees", "test-worktree")

    assert_path_exists worktree_path, "Worktree should be created"

    # Check instances were updated
    assert_equal worktree_path, instances[0][:directory]
    assert_equal File.join(worktree_path, "subdir"), instances[1][:directory]

    # Check that worktree is on a branch, not detached HEAD
    Dir.chdir(worktree_path) do
      output = `git rev-parse --abbrev-ref HEAD`.strip

      assert_equal "test-worktree", output, "Worktree should be on a branch named 'test-worktree'"
    end
  end

  def test_setup_worktrees_multiple_repos
    manager = ClaudeSwarm::WorktreeManager.new("multi-repo")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "other", directory: @other_repo_dir }
    ]

    manager.setup_worktrees(instances)

    # Check both worktrees were created
    worktree_path1 = File.join(@repo_dir, ".worktrees", "multi-repo")
    worktree_path2 = File.join(@other_repo_dir, ".worktrees", "multi-repo")

    assert_path_exists worktree_path1, "First worktree should be created"
    assert_path_exists worktree_path2, "Second worktree should be created"

    # Check instances were updated
    assert_equal worktree_path1, instances[0][:directory]
    assert_equal worktree_path2, instances[1][:directory]
  end

  def test_setup_worktrees_with_directories_array
    manager = ClaudeSwarm::WorktreeManager.new("array-test")

    instances = [
      {
        name: "multi",
        directories: [@repo_dir, File.join(@repo_dir, "subdir"), @other_repo_dir]
      }
    ]

    manager.setup_worktrees(instances)

    # Check all directories were mapped
    expected_dirs = [
      File.join(@repo_dir, ".worktrees", "array-test"),
      File.join(@repo_dir, ".worktrees", "array-test", "subdir"),
      File.join(@other_repo_dir, ".worktrees", "array-test")
    ]

    assert_equal expected_dirs, instances[0][:directories]
  end

  def test_map_to_worktree_path_non_git_directory
    manager = ClaudeSwarm::WorktreeManager.new("test")
    non_git_dir = File.join(@test_dir, "non-git")
    FileUtils.mkdir_p(non_git_dir)

    # Should return original path for non-git directories
    assert_equal non_git_dir, manager.map_to_worktree_path(non_git_dir, "test")
  end

  def test_cleanup_worktrees
    manager = ClaudeSwarm::WorktreeManager.new("cleanup-test")

    instances = [
      { name: "main", directory: @repo_dir },
      { name: "other", directory: @other_repo_dir }
    ]

    manager.setup_worktrees(instances)

    # Verify worktrees exist
    worktree_path1 = File.join(@repo_dir, ".worktrees", "cleanup-test")
    worktree_path2 = File.join(@other_repo_dir, ".worktrees", "cleanup-test")

    assert_path_exists worktree_path1
    assert_path_exists worktree_path2

    # Clean up
    manager.cleanup_worktrees

    # Verify worktrees are removed
    refute_path_exists worktree_path1, "First worktree should be removed"
    refute_path_exists worktree_path2, "Second worktree should be removed"
  end

  def test_session_metadata
    manager = ClaudeSwarm::WorktreeManager.new("metadata-test")

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    manager.setup_worktrees(instances)

    metadata = manager.session_metadata

    assert metadata[:enabled]
    assert_equal "metadata-test", metadata[:shared_name]
    assert_kind_of Hash, metadata[:created_paths]
    assert_equal File.join(@repo_dir, ".worktrees", "metadata-test"), metadata[:created_paths]["#{@repo_dir}:metadata-test"]
  end

  def test_existing_worktree_reuse
    # Create a worktree manually
    worktree_name = "existing-worktree"
    worktree_base = File.join(@repo_dir, ".worktrees")
    FileUtils.mkdir_p(worktree_base)
    worktree_path = File.join(worktree_base, worktree_name)

    Dir.chdir(@repo_dir) do
      system("git", "worktree", "add", "-b", worktree_name, worktree_path, "HEAD", out: File::NULL, err: File::NULL)
    end

    manager = ClaudeSwarm::WorktreeManager.new(worktree_name)

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    # Should reuse existing worktree without error
    manager.setup_worktrees(instances)

    assert_equal worktree_path, instances[0][:directory]
  end

  def test_existing_branch_reuse
    # Create a branch first
    branch_name = "existing-branch"
    Dir.chdir(@repo_dir) do
      system("git", "checkout", "-b", branch_name, out: File::NULL, err: File::NULL)
      system("git", "checkout", "main", out: File::NULL, err: File::NULL)
    end

    manager = ClaudeSwarm::WorktreeManager.new(branch_name)

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    # Should create worktree using existing branch
    manager.setup_worktrees(instances)

    worktree_path = File.join(@repo_dir, ".worktrees", branch_name)

    assert_path_exists worktree_path, "Worktree should be created"

    # Check that worktree is on the existing branch
    Dir.chdir(worktree_path) do
      output = `git rev-parse --abbrev-ref HEAD`.strip

      assert_equal branch_name, output, "Worktree should be on the existing branch"
    end
  end

  def test_empty_worktree_name_generates_name
    manager = ClaudeSwarm::WorktreeManager.new("")

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_default_thor_worktree_value_generates_name
    # When Thor gets --worktree without a value, it defaults to "worktree"
    manager = ClaudeSwarm::WorktreeManager.new("worktree")

    assert_match(/^worktree-[a-z0-9]{5}$/, manager.worktree_name)
  end

  def test_worktree_name_with_session_id
    # When session ID is provided, it should use it in the worktree name
    manager = ClaudeSwarm::WorktreeManager.new(nil, session_id: "20241206_143022")

    assert_equal "worktree-20241206_143022", manager.worktree_name
  end

  def test_empty_string_with_session_id
    # When empty string is passed with session ID
    manager = ClaudeSwarm::WorktreeManager.new("", session_id: "20241206_143022")

    assert_equal "worktree-20241206_143022", manager.worktree_name
  end

  def test_thor_default_with_session_id
    # When Thor default "worktree" is passed with session ID
    manager = ClaudeSwarm::WorktreeManager.new("worktree", session_id: "20241206_143022")

    assert_equal "worktree-20241206_143022", manager.worktree_name
  end

  def test_gitignore_created_in_worktrees_directory
    manager = ClaudeSwarm::WorktreeManager.new("test-gitignore")

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    manager.setup_worktrees(instances)

    # Check that .gitignore was created in .worktrees directory
    gitignore_path = File.join(@repo_dir, ".worktrees", ".gitignore")

    assert_path_exists gitignore_path, ".gitignore should be created in .worktrees"

    # Check contents
    gitignore_content = File.read(gitignore_path)

    assert_match(/\*/, gitignore_content, ".gitignore should contain wildcard to ignore all contents")
  end

  def test_per_instance_worktree_false
    manager = ClaudeSwarm::WorktreeManager.new("shared-worktree")

    instances = [
      { name: "main", directory: @repo_dir, worktree: true },
      { name: "other", directory: @other_repo_dir, worktree: false }
    ]

    manager.setup_worktrees(instances)

    # Main instance should be in worktree
    assert_equal File.join(@repo_dir, ".worktrees", "shared-worktree"), instances[0][:directory]

    # Other instance should keep original directory
    assert_equal @other_repo_dir, instances[1][:directory]
  end

  def test_per_instance_custom_worktree_name
    manager = ClaudeSwarm::WorktreeManager.new("shared-worktree")

    instances = [
      { name: "main", directory: @repo_dir, worktree: true },
      { name: "other", directory: @other_repo_dir, worktree: "custom-branch" }
    ]

    manager.setup_worktrees(instances)

    # Main instance should use shared worktree
    assert_equal File.join(@repo_dir, ".worktrees", "shared-worktree"), instances[0][:directory]

    # Other instance should use custom worktree
    assert_equal File.join(@other_repo_dir, ".worktrees", "custom-branch"), instances[1][:directory]
  end

  def test_per_instance_worktree_without_cli_option
    manager = ClaudeSwarm::WorktreeManager.new(nil)

    instances = [
      { name: "main", directory: @repo_dir }, # No worktree config, should not use worktree
      { name: "other", directory: @other_repo_dir, worktree: "feature-x" }
    ]

    manager.setup_worktrees(instances)

    # Main instance should keep original directory (no CLI option, no instance config)
    assert_equal @repo_dir, instances[0][:directory]

    # Other instance should use custom worktree
    assert_equal File.join(@other_repo_dir, ".worktrees", "feature-x"), instances[1][:directory]
  end

  def test_per_instance_worktree_true_without_cli_generates_name
    manager = ClaudeSwarm::WorktreeManager.new(nil)

    instances = [
      { name: "main", directory: @repo_dir, worktree: true }
    ]

    manager.setup_worktrees(instances)

    # Should generate a worktree with auto-generated name
    assert_match %r{/worktree-[a-z0-9]{5}$}, instances[0][:directory]
  end

  def test_cleanup_skips_worktree_with_uncommitted_changes
    manager = ClaudeSwarm::WorktreeManager.new("test-changes")

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    manager.setup_worktrees(instances)

    # Make changes in the worktree
    worktree_path = File.join(@repo_dir, ".worktrees", "test-changes")

    assert_path_exists worktree_path

    File.write(File.join(worktree_path, "new_file.txt"), "uncommitted content")

    # Capture output during cleanup
    output = capture_io { manager.cleanup_worktrees }.join

    # Verify worktree was NOT removed
    assert_path_exists worktree_path, "Worktree with uncommitted changes should not be removed"
    assert_match(/has uncommitted changes, skipping cleanup/, output)
  end

  def test_cleanup_skips_worktree_with_unpushed_commits
    manager = ClaudeSwarm::WorktreeManager.new("test-unpushed")

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    manager.setup_worktrees(instances)

    # Make a commit in the worktree
    worktree_path = File.join(@repo_dir, ".worktrees", "test-unpushed")

    assert_path_exists worktree_path

    Dir.chdir(worktree_path) do
      File.write("committed_file.txt", "committed content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Unpushed commit", out: File::NULL, err: File::NULL)
    end

    # Capture output during cleanup
    output = capture_io { manager.cleanup_worktrees }.join

    # Verify worktree was NOT removed
    assert_path_exists worktree_path, "Worktree with unpushed commits should not be removed"
    assert_match(/has unpushed commits, skipping cleanup/, output)
  end

  def test_cleanup_removes_clean_worktree
    manager = ClaudeSwarm::WorktreeManager.new("test-clean")

    instances = [
      { name: "main", directory: @repo_dir }
    ]

    manager.setup_worktrees(instances)

    worktree_path = File.join(@repo_dir, ".worktrees", "test-clean")

    assert_path_exists worktree_path

    # Cleanup should remove the clean worktree
    manager.cleanup_worktrees

    refute_path_exists worktree_path, "Clean worktree should be removed"
  end

  private

  def setup_git_repo(dir)
    FileUtils.mkdir_p(dir)
    Dir.chdir(dir) do
      system("git", "init", "--quiet", out: File::NULL, err: File::NULL)
      File.write("test.txt", "test content")
      system("git", "add", ".", out: File::NULL, err: File::NULL)
      system("git", "commit", "-m", "Initial commit", "--quiet", out: File::NULL, err: File::NULL)
    end

    # Create subdirectory
    FileUtils.mkdir_p(File.join(dir, "subdir"))
  end
end
