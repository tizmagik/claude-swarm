# frozen_string_literal: true

module Fixtures
  module SwarmConfigs
    def self.minimal
      <<~YAML
        version: 1
        swarm:
          name: "Minimal Swarm"
          main: lead
          instances:
            lead:
      YAML
    end

    def self.with_connections
      <<~YAML
        version: 1
        swarm:
          name: "Connected Swarm"
          main: lead
          instances:
            lead:
              connections: [backend, frontend]
            backend:
              directory: ./backend
            frontend:
              directory: ./frontend
      YAML
    end

    def self.with_tools
      <<~YAML
        version: 1
        swarm:
          name: "Tooled Swarm"
          main: lead
          instances:
            lead:
              tools: [Read, Edit, Bash, Grep]
      YAML
    end

    def self.with_tool_patterns
      <<~YAML
        version: 1
        swarm:
          name: "Pattern Swarm"
          main: lead
          instances:
            lead:
              tools:
                - Read
                - "Edit(*.js)"
                - "Bash(npm:*)"
                - "Grep(**/*.ts)"
      YAML
    end

    def self.with_mcps
      <<~YAML
        version: 1
        swarm:
          name: "MCP Swarm"
          main: lead
          instances:
            lead:
              mcps:
                - name: "stdio_server"
                  type: "stdio"
                  command: "test-server"
                  args: ["--port", "3000"]
                - name: "sse_server"
                  type: "sse"
                  url: "http://localhost:8080/events"
      YAML
    end

    def self.full_featured
      <<~YAML
        version: 1
        swarm:
          name: "Full Featured Swarm"
          main: lead
          instances:
            lead:
              directory: ./lead
              model: opus
              connections: [backend, frontend, tester]
              tools: [Read, Edit, Bash, Grep]
              prompt: "You are the lead developer coordinating the team"
              mcps:
                - name: "monitor"
                  type: "stdio"
                  command: "monitor-server"
            backend:
              directory: ./backend
              model: sonnet
              connections: [database]
              tools: ["Bash(python:*)", Edit, Read]
              prompt: "You handle API and backend logic"
            frontend:
              directory: ./frontend
              model: haiku
              tools: ["Edit(*.{js,jsx,ts,tsx})", "Bash(npm:*)", Read]
              prompt: "You build user interfaces"
            database:
              directory: ./db
              tools: ["Bash(psql:*,mysql:*)"]
            tester:
              directory: ./tests
              model: sonnet
              tools: ["Bash(jest:*,pytest:*)", Read, Edit]
              mcps:
                - name: "test_reporter"
                  type: "sse"
                  url: "http://localhost:9000/test-results"
      YAML
    end

    def self.circular_connections
      <<~YAML
        version: 1
        swarm:
          name: "Circular"
          main: a
          instances:
            a:
              connections: [b]
            b:
              connections: [c]
            c:
              connections: [a]
      YAML
    end
  end
end
