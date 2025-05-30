# Claude Swarm

Claude Swarm orchestrates multiple Claude Code instances as a collaborative AI development team. It enables running AI agents with specialized roles, tools, and directory contexts, communicating via MCP (Model Context Protocol) in a tree-like hierarchy. Define your swarm topology in simple YAML and let Claude instances delegate tasks through connected instances. Perfect for complex projects requiring specialized AI agents for frontend, backend, testing, DevOps, or research tasks.

## Installation

Install the gem by executing:

```bash
gem install claude_swarm
```

Or add it to your Gemfile:

```ruby
gem 'claude_swarm'
```

Then run:

```bash
bundle install
```

## Prerequisites

- Ruby 3.1.0 or higher
- Claude CLI installed and configured
- Any MCP servers you plan to use (optional)

## Usage

### Quick Start

1. Run `claude-swarm init` or create a `claude-swarm.yml` file in your project:

```yaml
version: 1
swarm:
  name: "My Dev Team"
  main: lead
  instances:
    lead:
      directory: .
      model: opus
      connections: [frontend, backend]
      tools: # Tools aren't required if you run it with `--vibe`
        - Read
        - Edit
        - Bash
    frontend:
      directory: ./frontend
      model: sonnet
      tools:
        - Edit
        - Write
        - Bash
    backend:
      directory: ./backend  
      model: sonnet
      tools:
        - Edit
        - Write
        - Bash
```

2. Start the swarm:

```bash
claude-swarm
```
or if you are feeling the vibes...
```bash
claude-swarm --vibe # That will allow ALL tools for all instances! Be Careful!
```

This will:
- Launch the main instance (lead) with connections to other instances
- The lead instance can communicate with the other instances via MCP
- All session files are stored in `.claude-swarm/sessions/{timestamp}/`

#### Multi-Level Swarm Example

Here's a more complex example showing specialized teams working on different parts of a project:

```yaml
version: 1
swarm:
  name: "Multi-Service Development Team"
  main: architect
  instances:
    architect:
      directory: .
      model: opus
      connections: [frontend_lead, backend_lead, mobile_lead, devops]
      prompt: "You are the system architect coordinating between different service teams"
      tools: [Read, Edit, WebSearch]
    
    frontend_lead:
      directory: ./web-frontend
      model: opus
      connections: [react_dev, css_expert]
      prompt: "You lead the web frontend team working with React"
      tools: [Read, Edit, Bash]
    
    react_dev:
      directory: ./web-frontend/src
      model: sonnet
      prompt: "You specialize in React components and state management"
      tools: [Edit, Write, "Bash(npm:*)"]
    
    css_expert:
      directory: ./web-frontend/styles
      model: sonnet
      prompt: "You handle all CSS and styling concerns"
      tools: [Edit, Write, Read]
    
    backend_lead:
      directory: ./api-server
      model: opus
      connections: [api_dev, database_expert]
      prompt: "You lead the API backend team"
      tools: [Read, Edit, Bash]
    
    api_dev:
      directory: ./api-server/src
      model: sonnet
      prompt: "You develop REST API endpoints"
      tools: [Edit, Write, Bash]
    
    database_expert:
      directory: ./api-server/db
      model: sonnet
      prompt: "You handle database schema and migrations"
      tools: [Edit, Write, "Bash(psql:*, migrate:*)"]
    
    mobile_lead:
      directory: ./mobile-app
      model: sonnet
      connections: [ios_dev, android_dev]
      prompt: "You coordinate mobile development across platforms"
      tools: [Read, Edit]
    
    ios_dev:
      directory: ./mobile-app/ios
      model: sonnet
      prompt: "You develop the iOS application"
      tools: [Edit, Write, "Bash(xcodebuild:*, pod:*)"]
    
    android_dev:
      directory: ./mobile-app/android
      model: sonnet
      prompt: "You develop the Android application"
      tools: [Edit, Write, "Bash(gradle:*, adb:*)"]
    
    devops:
      directory: ./infrastructure
      model: sonnet
      prompt: "You handle CI/CD and infrastructure"
      tools: [Read, Edit, "Bash(docker:*, kubectl:*)"]
```

In this setup:
- The architect (main instance) can delegate tasks to team leads
- Each team lead can work with their specialized developers
- Each instance is independent - connections create separate MCP server instances
- Teams work in isolated directories with role-appropriate tools


### Configuration Format

#### Top Level

```yaml
version: 1  # Required, currently only version 1 is supported
swarm:
  name: "Swarm Name"  # Display name for your swarm
  main: instance_key  # Which instance to launch as the main interface
  instances:
    # Instance definitions...
```

#### Instance Configuration

Each instance can have:

- **directory**: Working directory for this instance (can use ~ for home)
- **model**: Claude model to use (opus, sonnet, haiku)
- **connections**: Array of other instances this one can communicate with
- **tools**: Array of tools this instance can use
- **mcps**: Array of additional MCP servers to connect
- **prompt**: Custom system prompt to append to the instance

```yaml
instance_name:
  directory: ~/project/path
  model: opus
  connections: [other_instance1, other_instance2]
  prompt: "You are a specialized agent focused on..."
  tools:
    - Read
    - Edit
    - Write
    - Bash
    - WebFetch
    - WebSearch
  mcps:
    - name: server_name
      type: stdio
      command: command_to_run
      args: ["arg1", "arg2"]
      env:
        VAR1: value1
```

### MCP Server Types

#### stdio (Standard I/O)
```yaml
mcps:
  - name: my_tool
    type: stdio
    command: /path/to/executable
    args: ["--flag", "value"]
    env:
      API_KEY: "secret"
```

#### sse (Server-Sent Events)
```yaml
mcps:
  - name: remote_api
    type: sse
    url: "https://api.example.com/mcp"
```

### Tools

Specify which tools each instance can use:

```yaml
tools:
  - Bash           # Command execution
  - Edit           # File editing
  - Write          # File creation
  - Read           # File reading
  - WebFetch       # Fetch web content
  - WebSearch      # Search the web
```

Tools are passed to Claude using the `--allowedTools` flag with comma-separated values.

#### Tool Restrictions

You can restrict tools with pattern-based filters:

```yaml
tools:
  - Read                    # Unrestricted read access
  - Edit                    # Unrestricted edit access
  - "Bash(npm:*)"          # Only allow npm commands
  - "Bash(git:*, make:*)"  # Only allow git and make commands
```

### Examples

#### Full Stack Development Team

```yaml
version: 1
swarm:
  name: "Full Stack Team"
  main: architect
  instances:
    architect:
      directory: .
      model: opus
      connections: [frontend, backend, devops]
      prompt: "You are the lead architect responsible for system design and code quality"
      tools:
        - Read
        - Edit
        - WebSearch
        
    frontend:
      directory: ./frontend
      model: sonnet
      connections: [architect]
      prompt: "You specialize in React, TypeScript, and modern frontend development"
      tools:
        - Edit
        - Write
        - Bash
        
    backend:
      directory: ./backend
      model: sonnet
      connections: [architect, database]
      tools:
        - Edit
        - Write
        - Bash
        
    database:
      directory: ./db
      model: haiku
      tools:
        - Read
        - Bash
        
    devops:
      directory: .
      model: sonnet
      connections: [architect]
      tools:
        - Read
        - Edit
        - Bash
```

#### Research Team with External Tools

```yaml
version: 1
swarm:
  name: "Research Team"
  main: lead_researcher
  instances:
    lead_researcher:
      directory: ~/research
      model: opus
      connections: [data_analyst, writer]
      tools:
        - Read
        - WebSearch
        - WebFetch
      mcps:
        - name: arxiv
          type: sse
          url: "https://arxiv-mcp.example.com"
          
    data_analyst:
      directory: ~/research/data
      model: sonnet
      tools:
        - Read
        - Write
        - Bash
      mcps:
        - name: jupyter
          type: stdio
          command: jupyter-mcp
          args: ["--notebook-dir", "."]
          
    writer:
      directory: ~/research/papers
      model: sonnet
      tools:
        - Edit
        - Write
        - Read
```

### Command Line Options

```bash
# Use default claude-swarm.yml in current directory
claude-swarm

# Specify a different configuration file
claude-swarm --config my-swarm.yml
claude-swarm -c team-config.yml

# Run with --dangerously-skip-permissions for all instances
claude-swarm --vibe

# Run in non-interactive mode with a prompt
claude-swarm -p "Implement the new user authentication feature"
claude-swarm --prompt "Fix the bug in the payment module"

# Show version
claude-swarm version

# Internal command for MCP server (used by connected instances)
claude-swarm mcp-serve INSTANCE_NAME --config CONFIG_FILE --session-timestamp TIMESTAMP
```

## How It Works

1. **Configuration Parsing**: Claude Swarm reads your YAML configuration and validates it
2. **MCP Generation**: For each instance, it generates an MCP configuration file that includes:
   - Any explicitly defined MCP servers
   - MCP servers for each connected instance (using `claude-swarm mcp-serve`)
3. **Session Management**: Claude Swarm maintains session continuity:
   - Generates a shared session timestamp for all instances
   - Each instance can maintain its own Claude session ID
   - Sessions can be reset via the MCP server interface
4. **Main Instance Launch**: The main instance is launched with its MCP configuration, giving it access to all connected instances
5. **Inter-Instance Communication**: Connected instances expose themselves as MCP servers with these tools:
   - **task**: Execute tasks using Claude Code with configurable tools and return results
   - **session_info**: Get current Claude session information including ID and working directory
   - **reset_session**: Reset the Claude session for a fresh start
6. **Session Management**: All session files are organized in `.claude-swarm/sessions/{timestamp}/`:
   - MCP configuration files: `{instance_name}.mcp.json`
   - Session log: `session.log` with detailed request/response tracking

## Troubleshooting

### Common Issues

**"Configuration file not found"**
- Ensure `claude-swarm.yml` exists in the current directory
- Or specify the path with `--config`

**"Main instance not found in instances"**
- Check that your `main:` field references a valid instance key

**"Unknown instance in connections"**
- Verify all instances in `connections:` arrays are defined

**Permission Errors**
- Ensure Claude CLI is properly installed and accessible
- Check directory permissions for specified paths

### Debug Output

The swarm will display:
- Session directory location (`.claude-swarm/sessions/{timestamp}/`)
- Main instance details (model, directory, tools, connections)
- The exact command being run

### Session Files

Check the session directory `.claude-swarm/sessions/{timestamp}/` for:
- `session.log`: Detailed logs with request/response tracking
- `{instance}.mcp.json`: MCP configuration for each instance
- All files for a session are kept together for easy review

## Architecture

Claude Swarm consists of these core components:

- **ClaudeSwarm::CLI** (`cli.rb`): Thor-based command-line interface with `start` and `mcp-serve` commands
- **ClaudeSwarm::Configuration** (`configuration.rb`): YAML parser and validator with path expansion
- **ClaudeSwarm::McpGenerator** (`mcp_generator.rb`): Generates MCP JSON configs for each instance
- **ClaudeSwarm::Orchestrator** (`orchestrator.rb`): Launches the main Claude instance with shared session management
- **ClaudeSwarm::ClaudeCodeExecutor** (`claude_code_executor.rb`): Wrapper for executing Claude commands with session persistence
- **ClaudeSwarm::ClaudeMcpServer** (`claude_mcp_server.rb`): FastMCP-based server providing task execution, session info, and reset capabilities

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

### Development Commands

```bash
bin/setup              # Install dependencies
rake test             # Run the Minitest test suite
rake rubocop -A       # Run RuboCop linter with auto-fix
bin/console           # Start IRB session with gem loaded
bundle exec rake install    # Install gem locally
bundle exec rake release    # Release gem to RubyGems.org
rake                  # Default: runs both tests and RuboCop
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/parruda/claude-swarm.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).