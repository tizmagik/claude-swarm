# frozen_string_literal: true

require_relative "claude_swarm/version"
require_relative "claude_swarm/cli"
require_relative "claude_swarm/claude_code_executor"
require_relative "claude_swarm/claude_mcp_server"
require_relative "claude_swarm/permission_tool"
require_relative "claude_swarm/permission_mcp_server"

module ClaudeSwarm
  class Error < StandardError; end
end
