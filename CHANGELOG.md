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
