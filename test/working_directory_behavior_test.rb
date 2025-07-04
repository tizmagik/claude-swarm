# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class WorkingDirectoryBehaviorTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @test_root = Dir.mktmpdir

    # Create a project structure
    @project_dir = File.join(@test_root, "my_project")
    @config_dir = File.join(@project_dir, "config")
    @backend_dir = File.join(@project_dir, "backend")
    @frontend_dir = File.join(@project_dir, "frontend")

    FileUtils.mkdir_p(@config_dir)
    FileUtils.mkdir_p(@backend_dir)
    FileUtils.mkdir_p(@frontend_dir)

    # Create config file in a subdirectory
    @config_path = File.join(@config_dir, "claude-swarm.yml")
    File.write(@config_path, <<~YAML)
      version: 1
      swarm:
        name: "Working Dir Test"
        main: lead
        instances:
          lead:
            description: "Lead dev"
            directory: .
            model: sonnet
          backend:
            description: "Backend dev"
            directory: ./backend
            model: sonnet
          frontend:
            description: "Frontend dev"
            directory: ./frontend
            model: sonnet
    YAML
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@test_root)
  end

  def test_directories_resolved_from_launch_directory_not_config_directory
    # Launch from project root, config is in subdirectory
    Dir.chdir(@project_dir) do
      config = ClaudeSwarm::Configuration.new(@config_path, base_dir: Dir.pwd)

      # Verify all directories are resolved relative to launch directory (@project_dir)
      # not relative to config file directory (@config_dir)
      assert_equal(File.realpath(@project_dir), File.realpath(config.instances["lead"][:directory]))
      assert_equal(File.realpath(@backend_dir), File.realpath(config.instances["backend"][:directory]))
      assert_equal(File.realpath(@frontend_dir), File.realpath(config.instances["frontend"][:directory]))
    end
  end

  def test_directories_resolved_from_different_launch_location
    # Create another valid location to launch from
    other_launch_dir = File.join(@test_root, "other_location")
    FileUtils.mkdir_p(other_launch_dir)
    FileUtils.mkdir_p(File.join(other_launch_dir, "backend"))
    FileUtils.mkdir_p(File.join(other_launch_dir, "frontend"))

    # Launch from a different directory
    Dir.chdir(other_launch_dir) do
      config = ClaudeSwarm::Configuration.new(@config_path, base_dir: Dir.pwd)

      # Verify directories are resolved relative to current directory, not config location
      assert_equal(File.realpath(other_launch_dir), File.realpath(config.instances["lead"][:directory]))
      assert_equal(
        File.realpath(File.join(other_launch_dir, "backend")),
        File.realpath(config.instances["backend"][:directory]),
      )
      assert_equal(
        File.realpath(File.join(other_launch_dir, "frontend")),
        File.realpath(config.instances["frontend"][:directory]),
      )
    end
  end

  def test_absolute_paths_work_regardless_of_launch_directory
    # Update config with absolute paths
    File.write(@config_path, <<~YAML)
      version: 1
      swarm:
        name: "Absolute Path Test"
        main: lead
        instances:
          lead:
            description: "Lead with absolute path"
            directory: #{@project_dir}
            model: sonnet
          backend:
            description: "Backend with absolute path"
            directory: #{@backend_dir}
            model: sonnet
    YAML

    # Launch from anywhere - absolute paths should work
    Dir.chdir(@test_root) do
      config = ClaudeSwarm::Configuration.new(@config_path, base_dir: Dir.pwd)

      assert_equal(File.realpath(@project_dir), File.realpath(config.instances["lead"][:directory]))
      assert_equal(File.realpath(@backend_dir), File.realpath(config.instances["backend"][:directory]))
    end
  end
end
