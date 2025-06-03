## [0.1.8]

### Added
- **Disallowed tools support**: New `disallowed_tools` YAML key for explicitly denying specific tools (takes precedence over allowed tools)

### Changed
- **Renamed YAML key**: `tools` renamed to `allowed_tools` while maintaining backward compatibility
- Tool permissions now support both allow and deny patterns, with deny taking precedence
- Both `--allowedTools` and `--disallowedTools` are passed as comma-separated lists to Claude
- New CLI option `--stream-logs` - can only be used with `-p`

## [0.1.7]

### Added
- **Vibe mode support**: Per-instance `vibe: true` configuration to skip all permission checks for specific instances
- **Automatic permission management**: Built-in permission MCP server that handles tool authorization without manual approval
- **Permission logging**: All permission checks are logged to `.claude-swarm/sessions/{timestamp}/permissions.log`
- **Mixed permission modes**: Support for running some instances with full permissions while others remain restricted
- **New CLI command**: `claude-swarm tools-mcp` for starting a standalone permission management MCP server
- **Permission tool patterns**: Support for wildcard patterns in tool permissions (e.g., `mcp__frontend__*`)

### Changed
- Fixed `--system-prompt` to use `--append-system-prompt` for proper Claude Code integration
- Added `--permission-prompt-tool` flag pointing to `mcp__permissions__check_permission` when not in vibe mode
- Enhanced MCP generation to include a permission server for each instance (unless in vibe mode)

### Technical Details
- Permission checks use Fast MCP server with pattern matching for tool names
- Each instance can have its own permission configuration independent of global settings
- Permission decisions are made based on configured tool patterns with wildcard support

## [0.1.6]
- Refactor: move tools out of the ClaudeMcpServer class
- Move logging into code executor and save instance interaction streams to session.log
- Human readable logs with thoughts and tool calls

## [0.1.5]

### Changed
- **Improved command execution**: Switched from `exec` to `Dir.chdir` + `system` for better process handling and proper directory context
- Command arguments are now passed as an array instead of a shell string, eliminating the need for manual shell escaping
- Added default prompt behavior: when no `-p` flag is provided, a default prompt is added to help Claude understand it should start working

### Internal
- Updated test suite to match new command execution implementation
- Removed shellwords escaping tests as they're no longer needed with array-based command execution

## [0.1.4]

### Added
- **Required `description` field for instances**: Each instance must now have a description that clearly explains its role and specialization
- Dynamic task tool descriptions that include both the instance name and description (e.g., "Execute a task using Agent frontend_dev. Frontend developer specializing in React and modern web technologies")
- Description validation during configuration parsing - configurations without descriptions will fail with a clear error message

### Changed
- Updated all documentation examples to include meaningful instance descriptions
- The `claude-swarm init` command now generates a template with description fields

## [0.1.3]

### Fixed
- Fixed duplicate prompt arguments being passed to Claude Code executor, which could cause command execution failures

### Changed
- Improved logging to track request flow between instances using `from_instance` and `to_instance` fields instead of generic `instance_name`
- Added required `calling_instance` parameter to MCP server command to properly identify the source of requests in tree configurations
- Consolidated session files into a single directory structure (`.claude-swarm/sessions/<timestamp>/`)
- MCP configuration files are now stored alongside session logs in the same timestamped directory
- Session logs are now named `session.log` instead of `session_<timestamp>.log`
- Improved organization by keeping all session-related files together

## [0.1.2] - 2025-05-29

### Added
- Added `-p` / `--prompt` flag to pass prompts directly to the main Claude instance for non-interactive mode
- Output suppression when running with the `-p` flag for cleaner scripted usage

## [0.1.1] - 2025-05-24

- Initial release
