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
