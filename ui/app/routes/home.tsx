import { useState } from 'react';
import type { Route } from "./+types/home";
import SwarmSidebar from '../components/SwarmSidebar';
import SwarmCanvas from '../components/SwarmCanvas';
import AgentMcpPanels from '../components/AgentMcpPanels';
import type { SwarmSummary } from '../components/SwarmSidebar';
import { Zap, Play } from 'lucide-react';

export function meta({}: Route.MetaArgs) {
  return [
    { title: "Claude Swarm UI" },
    { name: "description", content: "Web interface for Claude Swarm orchestration" },
  ];
}

interface AgentNode {
  id: string;
  name: string;
  description: string;
  x: number;
  y: number;
  tools: string[];
  mcps: string[];
  model: string;
  connections: string[];
}

interface Connection {
  from: string;
  to: string;
}

export default function Home() {
  const [selectedSwarm, setSelectedSwarm] = useState<SwarmSummary | null>(null);
  const [refreshTrigger, setRefreshTrigger] = useState(0);
  const [nodes, setNodes] = useState<AgentNode[]>([]);
  const [connections, setConnections] = useState<Connection[]>([]);

  const handleSwarmSelect = (swarm: SwarmSummary) => {
    console.log('Swarm selected:', swarm);
    setSelectedSwarm(swarm);
    // TODO: Load existing nodes from swarm configuration
    loadSwarmNodes(swarm);
  };

  const loadSwarmNodes = async (swarm: SwarmSummary) => {
    console.log('Loading swarm nodes for:', swarm);
    try {
      const response = await fetch(`/api/swarms/${swarm.filename}`);
      console.log('API response status:', response.status);
      if (response.ok) {
        const config = await response.json();
        console.log('Loaded config:', config);
        // Convert swarm instances to visual nodes
        const swarmNodes: AgentNode[] = Object.entries(config.swarm.instances || {}).map(([name, instance]: [string, any], index) => ({
          id: name,
          name: name.charAt(0).toUpperCase() + name.slice(1).replace(/_/g, ' '),
          description: instance.description || 'No description',
          x: 200 + (index % 3) * 250,
          y: 150 + Math.floor(index / 3) * 200,
          tools: instance.allowed_tools || instance.tools || [],
          mcps: instance.mcps?.map((mcp: any) => mcp.name) || [],
          model: instance.model || 'sonnet',
          connections: instance.connections || []
        }));
        
        console.log('Created swarm nodes:', swarmNodes);
        
        // Convert connections
        const swarmConnections: Connection[] = [];
        Object.entries(config.swarm.instances || {}).forEach(([name, instance]: [string, any]) => {
          (instance.connections || []).forEach((target: string) => {
            swarmConnections.push({ from: name, to: target });
          });
        });
        
        console.log('Created connections:', swarmConnections);
        console.log('Setting nodes state with:', swarmNodes);
        setNodes(swarmNodes);
        setConnections(swarmConnections);
      } else {
        console.error('API response not ok:', response.status, response.statusText);
      }
    } catch (error) {
      console.error('Failed to load swarm nodes:', error);
    }
  };

  const handleSwarmUpdated = () => {
    setRefreshTrigger(prev => prev + 1);
  };

  const handleNodeUpdate = (newNodes: AgentNode[]) => {
    setNodes(newNodes);
  };

  const handleConnectionUpdate = (newConnections: Connection[]) => {
    setConnections(newConnections);
  };

  return (
    <div className="min-h-screen bg-slate-950">
      <div className="flex h-screen overflow-hidden">
        {/* Left Sidebar - Swarms */}
        <div className="flex-shrink-0">
          <SwarmSidebar 
            onSwarmSelect={handleSwarmSelect}
            selectedSwarm={selectedSwarm}
            key={refreshTrigger}
          />
        </div>
        
        {/* Main Canvas Area */}
        <div className="flex-1 flex flex-col min-w-0">
          {selectedSwarm ? (
            <>
              {/* Canvas - Top portion */}
              <div className="flex-1 min-h-0">
                <SwarmCanvas
                  swarmName={selectedSwarm.name}
                  nodes={nodes}
                  connections={connections}
                  onNodeUpdate={handleNodeUpdate}
                  onConnectionUpdate={handleConnectionUpdate}
                />
              </div>
              
              {/* Terminal - Bottom portion */}
              <div className="h-24 lg:h-32 border-t border-slate-700 bg-slate-950 text-emerald-400 font-mono text-sm flex-shrink-0">
                <div className="p-3 lg:p-4 h-full flex flex-col">
                  <div className="flex items-center mb-2">
                    <Play className="w-3 h-3 text-emerald-400 mr-2 animate-pulse" />
                    <div className="text-emerald-400 font-medium text-xs lg:text-sm">Running swarm...</div>
                  </div>
                  <div className="text-slate-500 text-xs flex-1 overflow-y-auto">
                    claude-swarm output will be streamed here
                  </div>
                </div>
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center bg-slate-950 p-4">
              <div className="text-center text-slate-400 max-w-lg">
                <Zap className="w-16 h-16 lg:w-20 lg:h-20 mx-auto mb-6 text-blue-400" />
                <h2 className="text-2xl lg:text-3xl font-bold mb-4 text-white">Claude Swarm UI</h2>
                <p className="text-base lg:text-lg mb-8 leading-relaxed">Orchestrate multiple AI agents to work together as a collaborative development team.</p>
                <div className="text-sm text-slate-500">
                  Select a swarm from the sidebar to get started, or create a new one.
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Right Sidebar - Agents & MCPs */}
        <div className="flex-shrink-0">
          <AgentMcpPanels />
        </div>
      </div>
    </div>
  );
}
