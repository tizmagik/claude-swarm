# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Swarm is a Ruby gem that orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol).

## Development Commands

### Setup
```bash
bin/setup              # Install dependencies
```

### Testing
```bash
rake test             # Run the Minitest test suite
```

### Linting
```bash
rake rubocop -A       # Run RuboCop linter to auto fix problems
```

### Development Console
```bash
bin/console           # Start IRB session with gem loaded
```

### Build & Release
```bash
bundle exec rake install    # Install gem locally
bundle exec rake release    # Release gem to RubyGems.org
```

### Default Task
```bash
rake                  # Runs both tests and RuboCop
```

## Architecture

The gem is fully implemented with the following components:

### Core Classes

- **ClaudeSwarm::CLI** (`lib/claude_swarm/cli.rb`): Thor-based CLI that handles command parsing and orchestration
- **ClaudeSwarm::Configuration** (`lib/claude_swarm/configuration.rb`): YAML parser and validator for swarm configurations
- **ClaudeSwarm::McpGenerator** (`lib/claude_swarm/mcp_generator.rb`): Generates MCP JSON configurations for each instance
- **ClaudeSwarm::Orchestrator** (`lib/claude_swarm/orchestrator.rb`): Launches the main Claude instance with proper configuration

### Key Features

1. **YAML Configuration**: Define swarms with instances, connections, tools, and MCP servers
2. **Inter-Instance Communication**: Instances connect via MCP using `claude mcp serve` with `-p` flag
3. **Tool Restrictions**: Support for pattern-based tool restrictions (e.g., `Bash(npm:*)`)
4. **Multiple MCP Types**: Supports both stdio and SSE MCP server types
5. **Automatic MCP Generation**: Creates `.claude-swarm/` directory with MCP configs
6. **Custom System Prompts**: Each instance can have a custom prompt via `--append-system-prompt`

### How It Works

1. User creates a `claude-swarm.yml` file defining the swarm topology
2. Running `claude-swarm` parses the configuration and validates it
3. MCP configuration files are generated for each instance in `.claude-swarm/`
4. The main instance is launched with `exec`, replacing the current process
5. Connected instances are available as MCP servers to the main instance

### Configuration Example

```yaml
version: 1
swarm:
  name: "Dev Team"
  main: lead
  instances:
    lead:
      directory: .
      model: opus
      connections: [frontend, backend]
      prompt: "You are the lead developer coordinating the team"
      tools: [Read, Edit, Bash]
    frontend:
      directory: ./frontend
      model: sonnet
      prompt: "You specialize in frontend development with React"
      tools: [Edit, Write, "Bash(npm:*)"]
```

## Testing

The gem includes basic tests for version number and CLI existence. Additional tests should be added for:
- Configuration parsing and validation
- MCP generation logic
- Error handling scenarios

## Dependencies

- **thor** (~> 1.3): Command-line interface framework
- **yaml**: Built-in Ruby YAML parser (no explicit dependency needed)
