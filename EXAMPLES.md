## Draft use case

Imagine you're working in the storefront-web repository. Page load times doubled yesterday. You're not sure why. 

To investigate today you'd use a generalized Claude. It has access to dozens of MCP tools. Tools to read data from BigQuery. Tools to crawl repositories. Tools to checkout code it needs. Tools for GitHub interactions. Tools for Kafka. Tools for file operations.

You need to query BigQuery to pinpoint when the performance degraded. You also need to check recent gem upgrades. But Claude doesn't know which gem repositories to look at. You have to provide context about where to find gem source code. You have to guide it through vendor directories or gem installation paths.

Claude might be able to do this. But with dozens of MCP tools loaded and lots of context it can be overwhelmed and unfocused. It struggles to pick the right tools. It struggles to understand which repos to read. It struggles to keep context in mind while switching between data analysis and code exploration.

## Enter Claude-Swarm

```
Without Swarm:                         With Claude-Swarm:
                                      
┌──────────────────────────────┐       ┌─────────────────────────────────┐
│           You                │       │            You                  │
└──────────────┬───────────────┘       └──────────────┬──────────────────┘
               │                                      │
               v                                      v
┌──────────────────────────────┐       ┌─────────────────────────────────┐
│     Generalized Claude       │       │         Coordinator             │
│                              │       │                                 │
│ [30+ MCP Tools]              │       │      [Task delegation]          │
│ • BigQuery tools             │       └──────────────┬──────────────────┘
│ • File tools                 │                      │
│ • Git tools                  │       ┌──────────────┼──────────────────┐
│ • GitHub tools               │       │              │                  │
│ • Kafka tools                │       v              v                  v
│ • ...                        │     ┌────────┐  ┌────────┐    ┌────────┐
│                              │     │Data    │  │Code    │    │PR      │
│ Overwhelmed &                │     │Expert  │  │Expert  │    │Expert  │
│ Context switching            │     │[BQ]    │  │[Files] │    │[GitHub]│
└──────────────────────────────┘     └────────┘  └────────┘    └────────┘
```

Claude-swarm is one AI that can hire specialist AIs. Each specialist lives in one domain. You talk to the manager not the specialists. Manager coordinates and gives you answers.

It's NOT multiple AIs running at once. It's ONE AI with "summon expert" superpowers. Experts appear and answer questions. Then they disappear.

## Three Key Features

### Domain Isolation
- Data expert can pull BigQuery and performance metrics
- Code expert lives in gem source directory
- PR Expert only cares about writing a quality PR
- Each expert focused on their domain. Each expert with custom context and prompts.

### Selective Tool Access
- Data expert ONLY gets BigQuery and Kafka tools (prompt it with best practices and context for querying)
- Code expert ONLY gets file and git tools. It instantiates in a specific repo (Prompt it and provide it special context)
- PR expert ONLY gets PR/GH tools. Can prompt it with best practices for PR submissions/context

### Coordinated Intelligence
- You ask one question
- Get answers from multiple domains, each with specialized context and prompts
- "Why are pages loading slowly?"
- Data expert finds timing spike at 2pm yesterday
- Code expert finds the problem
- Code expert fixes the problem
- PR Expert creates the PR with your specifications

## Example Configuration

```yaml
version: 1
swarm:
  name: "Performance Investigation"
  main: coordinator
  instances:
    coordinator:
      description: "Lead developer coordinating performance investigation"
      directory: ~/storefront-web
      connections: [data_expert, code_expert, pr_expert]
      prompt: |
        You are a senior lead developer coordinating a performance investigation team.
        Your role is to delegate tasks to specialists and synthesize their findings.
        
        When investigating performance issues:
        1. Start with data_expert to identify when/where problems occurred
        2. Use code_expert to analyze code changes and identify root causes
        3. Use pr_expert to implement fixes via pull requests
        
        Always provide clear, actionable summaries to the user.
      
    data_expert:
      description: "Analyzes performance metrics and data"
      directory: ~/analysis
      tools: [data_mcp_portal_find_tables, data_mcp_portal_query]
      prompt: |
        You are a data analyst specializing in web performance metrics.
        You have access to BigQuery and performance monitoring data.
        
        When analyzing performance issues:
        - Always use partition filters (date-based) to limit query scope
        - Look for correlations between timing spikes and deployments
        - Focus on p95/p99 latencies, not just averages
        - Identify affected user segments and geographic regions
        
        Provide specific timestamps and quantified impact metrics.
      
    code_expert:
      description: "Analyzes code, dependencies, and implementations"
      directory: ~/gems/http-client
      tools: [read, grep, glob, git]
      prompt: |
        You are a senior Ruby developer specializing in performance optimization.
        You work primarily with gems, dependencies, and low-level implementations.
        
        When investigating performance issues:
        - Check recent version changes in Gemfile.lock
        - Look for connection pooling, caching, and resource management patterns
        - Identify blocking I/O operations and inefficient algorithms
        - Consider memory allocation and garbage collection impacts
        
        Focus on actionable code-level fixes and configuration changes.
        
    pr_expert:
      description: "Creates high-quality pull requests"
      directory: ~/storefront-web
      tools: [read, write, gh_cli, git]
      prompt: |
        You are a senior developer focused on creating excellent pull requests.
        
        For performance fixes:
        - Write clear, specific titles: "Fix: Enable HTTP connection pooling for 40% latency reduction"
        - Include before/after performance metrics in description
        - Add links to supporting data analysis
        - Include deployment considerations and rollback plans
        - Add relevant reviewers based on affected systems
        
        Always follow the team's PR template and coding standards.
```

## Investigation and Fix Flow

**You:** "Why are pages loading slowly?"

**Coordinator asks data_expert:** "When did latency spike and what's the impact?"

**Data expert:** 
```sql
-- Query shows latency spike at 2:15 PM yesterday
-- P95 response time increased from 250ms to 890ms
-- Affecting 15% of traffic, primarily checkout flows
```

**Coordinator asks code_expert:** "What changed around 2:15 PM yesterday that could cause this?"

**Code expert:** 
```ruby
# Gemfile.lock shows http-client gem updated from 3.1.9 to 3.2.0 at 2:14 PM
# Version 3.2.0 changelog: "Removed automatic connection pooling for thread safety"
# Now creates new HTTP connection per request instead of reusing connections
```

**Coordinator:** "The http-client gem update removed connection pooling, causing 3x latency increase during checkout."

**You:** "Fix this and create a PR"

**Code expert:** "Two options: downgrade to 3.1.9 or configure explicit pooling with `pool_size: 10` in initializer"

**PR expert:** "Created PR #1234: 'Fix: Enable HTTP connection pooling for 40% latency reduction' with performance benchmarks and rollback plan"

