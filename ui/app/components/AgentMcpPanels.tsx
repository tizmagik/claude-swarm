import { useState, useEffect } from 'react';

interface AgentTemplate {
  id: string;
  name: string;
  description: string;
  model?: string;
  prompt?: string;
  allowed_tools?: string[];
  disallowed_tools?: string[];
  mcps?: Array<{
    name: string;
    type: 'stdio' | 'sse';
    command?: string;
    args?: string[];
    url?: string;
  }>;
}

interface McpTool {
  id: string;
  name: string;
  type: 'stdio' | 'sse';
  command?: string;
  args?: string[];
  url?: string;
  description?: string;
}

export default function AgentMcpPanels() {
  const [agents, setAgents] = useState<AgentTemplate[]>([]);
  const [mcps, setMcps] = useState<McpTool[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      // Load agent templates
      const agentResponse = await fetch('/api/agent-templates');
      let agentData: AgentTemplate[] = [];
      if (agentResponse.ok) {
        agentData = await agentResponse.json();
      }

      // Load MCP tools
      const mcpResponse = await fetch('/api/mcp-tools');
      let mcpData: McpTool[] = [];
      if (mcpResponse.ok) {
        mcpData = await mcpResponse.json();
      }

      // If no data exists, create some default templates
      if (agentData.length === 0) {
        agentData = [
          {
            id: 'lead-developer',
            name: 'Lead Developer',
            description: 'Coordinates team and makes architectural decisions',
            model: 'opus',
            allowed_tools: ['Read', 'Edit', 'Bash', 'Write']
          },
          {
            id: 'frontend-react-developer',
            name: 'Frontend React Developer',
            description: 'Specializes in React and modern web technologies',
            model: 'sonnet',
            allowed_tools: ['Read', 'Edit', 'Write', 'Bash(npm:*)', 'Bash(yarn:*)']
          },
          {
            id: 'backend-rails-developer',
            name: 'Backend Rails Developer',
            description: 'Focuses on APIs, databases, and server architecture',
            model: 'sonnet',
            allowed_tools: ['Read', 'Edit', 'Write', 'Bash']
          },
          {
            id: 'devops-engineer',
            name: 'DevOps Engineer',
            description: 'Manages infrastructure, CI/CD, and deployments',
            model: 'sonnet',
            allowed_tools: ['Read', 'Edit', 'Write', 'Bash(docker:*)', 'Bash(kubectl:*)']
          }
        ];
      }

      if (mcpData.length === 0) {
        mcpData = [
          {
            id: 'playwright',
            name: 'Playwright',
            type: 'stdio',
            command: 'npx',
            args: ['@playwright/test'],
            description: 'Browser automation and testing'
          },
          {
            id: 'vault-mcp',
            name: 'Vault MCP',
            type: 'stdio',
            command: 'vault-mcp-server',
            description: 'HashiCorp Vault integration'
          },
          {
            id: 'gsuite-mcp',
            name: 'GSuite MCP',
            type: 'stdio',
            command: 'gsuite-mcp-server',
            description: 'Google Workspace integration'
          },
          {
            id: 'figma-mcp',
            name: 'Figma MCP',
            type: 'stdio',
            command: 'figma-mcp-server',
            description: 'Figma design tool integration'
          }
        ];
      }

      setAgents(agentData);
      setMcps(mcpData);
    } catch (error) {
      console.error('Failed to load data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleDragStart = (e: React.DragEvent, item: AgentTemplate | McpTool, type: 'agent' | 'mcp') => {
    console.log('Drag start:', { item: item.name, type });
    const dragData = JSON.stringify({ item, type });
    console.log('Setting drag data:', dragData);
    e.dataTransfer.setData('application/json', dragData);
    e.dataTransfer.effectAllowed = 'copy';
  };

  if (loading) {
    return (
      <div className="w-80 bg-gray-100 border-l border-gray-300 p-4">
        <div className="animate-pulse">Loading...</div>
      </div>
    );
  }

  return (
    <div className="w-80 bg-gray-100 border-l border-gray-300 p-4 flex flex-col h-full">
      {/* Agents Section */}
      <div className="flex-1 mb-6">
        <h2 className="text-lg font-semibold mb-4 text-gray-800">Agents</h2>
        <div className="space-y-2 overflow-y-auto">
          {agents.map((agent) => (
            <div
              key={agent.id}
              draggable
              onDragStart={(e) => handleDragStart(e, agent, 'agent')}
              className="p-3 bg-gray-800 text-white rounded-lg cursor-grab hover:bg-gray-700 transition-colors border border-gray-600"
            >
              <div className="font-medium text-sm">{agent.name}</div>
              <div className="text-xs text-gray-300 mt-1 line-clamp-2">
                {agent.description}
              </div>
              {agent.model && (
                <div className="text-xs text-blue-300 mt-1">
                  Model: {agent.model}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* MCPs Section */}
      <div className="flex-1">
        <h2 className="text-lg font-semibold mb-4 text-gray-800">MCPs</h2>
        <div className="space-y-2 overflow-y-auto">
          {mcps.map((mcp) => (
            <div
              key={mcp.id}
              draggable
              onDragStart={(e) => handleDragStart(e, mcp, 'mcp')}
              className="p-3 bg-gray-800 text-white rounded-lg cursor-grab hover:bg-gray-700 transition-colors border border-gray-600"
            >
              <div className="font-medium text-sm">{mcp.name}</div>
              {mcp.description && (
                <div className="text-xs text-gray-300 mt-1 line-clamp-2">
                  {mcp.description}
                </div>
              )}
              <div className="text-xs text-purple-300 mt-1">
                Type: {mcp.type}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}