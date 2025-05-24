# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "claude_swarm"

require "minitest/autorun"
require_relative "fixtures/swarm_configs"
require_relative "helpers/test_helpers"
