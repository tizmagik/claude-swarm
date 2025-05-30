# frozen_string_literal: true

module Fixtures
  module SwarmConfigsInvalid
    def self.invalid_version
      <<~YAML
        version: 2
        swarm:
          name: "Invalid"
          main: lead
          instances:
            lead:
              description: "Lead instance"
      YAML
    end

    def self.missing_main
      <<~YAML
        version: 1
        swarm:
          name: "No Main"
          instances:
            lead:
              description: "Lead instance"
      YAML
    end

    def self.invalid_connection
      <<~YAML
        version: 1
        swarm:
          name: "Bad Connection"
          main: lead
          instances:
            lead:
              description: "Lead instance"
              connections: [nonexistent]
      YAML
    end

    def self.missing_description
      <<~YAML
        version: 1
        swarm:
          name: "Missing Description"
          main: lead
          instances:
            lead:
              directory: .
      YAML
    end
  end
end
