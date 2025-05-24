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
      YAML
    end

    def self.missing_main
      <<~YAML
        version: 1
        swarm:
          name: "No Main"
          instances:
            lead:
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
              connections: [nonexistent]
      YAML
    end
  end
end
