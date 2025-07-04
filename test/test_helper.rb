# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "claude_swarm"

require "minitest/autorun"
require_relative "fixtures/swarm_configs"
require_relative "helpers/test_helpers"

# Set up a temporary home directory for all tests
require "tmpdir"
TEST_SWARM_HOME = Dir.mktmpdir("claude-swarm-test")
ENV["CLAUDE_SWARM_HOME"] = TEST_SWARM_HOME

# Clean up the test home directory after all tests
Minitest.after_run do
  FileUtils.rm_rf(TEST_SWARM_HOME)
end
