import { useState } from 'react';
import type { Route } from "./+types/home";
import SwarmSidebar from '../components/SwarmSidebar';
import SwarmCanvas from '../components/SwarmCanvas';
import AgentMcpPanels from '../components/AgentMcpPanels';
import type { SwarmSummary } from '../components/SwarmSidebar';

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
    <div className="min-h-screen bg-gray-900">
      <div className="flex h-screen">
        {/* Left Sidebar - Swarms */}
        <SwarmSidebar 
          onSwarmSelect={handleSwarmSelect}
          selectedSwarm={selectedSwarm}
          key={refreshTrigger}
        />
        
        {/* Main Canvas Area */}
        <div className="flex-1 flex flex-col">
          {selectedSwarm ? (
            <>
              {/* Canvas - Top 3/4 */}
              <div className="flex-1">
                <SwarmCanvas
                  swarmName={selectedSwarm.name}
                  nodes={nodes}
                  connections={connections}
                  onNodeUpdate={handleNodeUpdate}
                  onConnectionUpdate={handleConnectionUpdate}
                />
              </div>
              
              {/* Terminal - Bottom 1/4 */}
              <div className="h-32 border-t border-gray-700 bg-black text-green-400 font-mono text-sm">
                <div className="p-4">
                  <div className="text-green-400 mb-1">Running ...</div>
                  <div className="text-gray-500">
                    claude-swarm output streamed here
                  </div>
                </div>
              </div>
            </>
          ) : (
            <div className="flex-1 flex items-center justify-center">
              <div className="text-center text-gray-400">
                <h2 className="text-2xl font-semibold mb-2">Claude Swarm UI</h2>
                <p>Select a swarm from the sidebar to get started, or create a new one.</p>
              </div>
            </div>
          )}
        </div>

        {/* Right Sidebar - Agents & MCPs */}
        <AgentMcpPanels />
      </div>
    </div>
  );
}
