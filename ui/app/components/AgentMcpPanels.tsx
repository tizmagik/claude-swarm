import { useState, useEffect } from 'react';
import { Bot, Settings, Wrench, Crown, Monitor, Server, Building, TestTube, Shield, BarChart3, Palette } from 'lucide-react';

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

  const categoryColors = {
    leadership: 'bg-amber-500',
    frontend: 'bg-blue-500',
    backend: 'bg-emerald-500',
    infrastructure: 'bg-purple-500',
    testing: 'bg-red-500',
    security: 'bg-orange-500',
    productivity: 'bg-cyan-500',
    design: 'bg-pink-500',
  } as const;

  const categoryIcons = {
    leadership: Crown,
    frontend: Monitor,
    backend: Server,
    infrastructure: Building,
    testing: TestTube,
    security: Shield,
    productivity: BarChart3,
    design: Palette,
  } as const;

  const getAgentCategory = (name: string): keyof typeof categoryColors => {
    if (name.toLowerCase().includes('lead')) return 'leadership';
    if (name.toLowerCase().includes('frontend') || name.toLowerCase().includes('react')) return 'frontend';
    if (name.toLowerCase().includes('backend') || name.toLowerCase().includes('rails')) return 'backend';
    if (name.toLowerCase().includes('devops')) return 'infrastructure';
    return 'backend';
  };

  const getMcpCategory = (name: string): keyof typeof categoryColors => {
    if (name.toLowerCase().includes('playwright') || name.toLowerCase().includes('test')) return 'testing';
    if (name.toLowerCase().includes('vault') || name.toLowerCase().includes('security')) return 'security';
    if (name.toLowerCase().includes('gsuite') || name.toLowerCase().includes('workspace')) return 'productivity';
    if (name.toLowerCase().includes('figma') || name.toLowerCase().includes('design')) return 'design';
    return 'testing';
  };

  if (loading) {
    return (
      <div className="w-80 bg-slate-900 border-l border-slate-700 p-6">
        <div className="text-center">
          <div className="animate-spin text-4xl mb-4">⚡</div>
          <div className="text-slate-400">Loading resources...</div>
        </div>
      </div>
    );
  }

  return (
    <div className="w-80 lg:w-80 md:w-72 sm:w-64 bg-slate-900 border-l border-slate-700 flex flex-col h-full">
      {/* Agents Section */}
      <div className="flex-1 p-3 lg:p-4 border-b border-slate-700 min-h-0">
        <div className="flex items-center mb-3 lg:mb-4">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Bot className="w-5 h-5 mr-2 text-blue-400" />
            <span className="hidden sm:inline">Agents</span>
          </h2>
        </div>
        <div className="text-slate-300 text-xs lg:text-sm mb-3 lg:mb-4 hidden sm:block">
          Drag agents to add them to your swarm
        </div>
        <div className="space-y-2 lg:space-y-3 overflow-y-auto" style={{ maxHeight: 'calc(50vh - 120px)' }}>
          {agents.map((agent) => {
            const category = getAgentCategory(agent.name);
            const IconComponent = categoryIcons[category];
            return (
              <div
                key={agent.id}
                draggable
                onDragStart={(e) => handleDragStart(e, agent, 'agent')}
                className="p-3 lg:p-4 bg-slate-800 rounded-xl border border-slate-700 cursor-grab hover:bg-slate-750 hover:border-slate-600 hover:shadow-lg transition-all duration-200 group"
              >
                <div className="flex items-center mb-2">
                  <div className={`w-6 h-6 lg:w-8 lg:h-8 rounded-lg ${categoryColors[category]} flex items-center justify-center text-white mr-2 lg:mr-3`}>
                    <IconComponent className="w-3 h-3 lg:w-4 lg:h-4" />
                  </div>
                  <div className="font-semibold text-white text-xs lg:text-sm group-hover:text-blue-300 transition-colors truncate">
                    {agent.name}
                  </div>
                </div>
                <div className="text-xs text-slate-300 mb-2 lg:mb-3 leading-relaxed line-clamp-2 hidden sm:block">
                  {agent.description}
                </div>
                <div className="flex justify-between items-center text-xs">
                  <span className="text-slate-400 capitalize px-2 py-1 bg-slate-700 rounded-full hidden sm:inline">
                    {category}
                  </span>
                  {agent.model && (
                    <span className="text-white px-2 py-1 bg-slate-700 rounded-full font-medium">
                      {agent.model}
                    </span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* MCPs Section */}
      <div className="flex-1 p-3 lg:p-4 min-h-0">
        <div className="flex items-center mb-3 lg:mb-4">
          <h2 className="text-lg lg:text-xl font-bold text-white flex items-center">
            <Wrench className="w-5 h-5 mr-2 text-purple-400" />
            <span className="hidden sm:inline">MCPs</span>
          </h2>
        </div>
        <div className="text-slate-300 text-xs lg:text-sm mb-3 lg:mb-4 hidden sm:block">
          Available MCP tools and integrations
        </div>
        <div className="space-y-2 lg:space-y-3 overflow-y-auto" style={{ maxHeight: 'calc(50vh - 120px)' }}>
          {mcps.map((mcp) => {
            const category = getMcpCategory(mcp.name);
            const IconComponent = categoryIcons[category];
            return (
              <div
                key={mcp.id}
                draggable
                onDragStart={(e) => handleDragStart(e, mcp, 'mcp')}
                className="p-3 lg:p-4 bg-slate-800 rounded-xl border border-slate-700 cursor-grab hover:bg-slate-750 hover:border-slate-600 hover:shadow-lg transition-all duration-200 group"
              >
                <div className="flex items-center mb-2">
                  <div className={`w-6 h-6 lg:w-8 lg:h-8 rounded-lg ${categoryColors[category]} flex items-center justify-center text-white mr-2 lg:mr-3`}>
                    <IconComponent className="w-3 h-3 lg:w-4 lg:h-4" />
                  </div>
                  <div className="font-semibold text-white text-xs lg:text-sm group-hover:text-purple-300 transition-colors truncate">
                    {mcp.name}
                  </div>
                </div>
                {mcp.description && (
                  <div className="text-xs text-slate-300 mb-2 lg:mb-3 leading-relaxed line-clamp-2 hidden sm:block">
                    {mcp.description}
                  </div>
                )}
                <div className="flex justify-between items-center text-xs">
                  <span className="text-slate-400 capitalize px-2 py-1 bg-slate-700 rounded-full hidden sm:inline">
                    {category}
                  </span>
                  <span className="text-white px-2 py-1 bg-slate-700 rounded-full font-medium">
                    {mcp.type}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}