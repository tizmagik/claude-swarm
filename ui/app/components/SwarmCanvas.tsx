import { useState, useRef, useCallback, useMemo, useEffect } from 'react';

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

interface SwarmCanvasProps {
  swarmName: string;
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
  onConnectionUpdate: (connections: Connection[]) => void;
}

// Client-side only ReactFlow component
function ReactFlowCanvas({ 
  nodes, 
  connections 
}: { 
  nodes: AgentNode[], 
  connections: Connection[] 
}) {
  const [ReactFlow, setReactFlow] = useState<any>(null);
  const [Controls, setControls] = useState<any>(null);
  const [Background, setBackground] = useState<any>(null);

  useEffect(() => {
    // Import ReactFlow only on client-side
    import('@xyflow/react').then((module) => {
      setReactFlow(() => module.ReactFlow);
      setControls(() => module.Controls);
      setBackground(() => module.Background);
    });
    // Import ReactFlow styles
    import('@xyflow/react/dist/style.css');
  }, []);

  const reactFlowNodes = useMemo(() => {
    return nodes.map((node) => ({
      id: node.id,
      type: 'default',
      position: { x: node.x, y: node.y },
      data: { label: node.name },
    }));
  }, [nodes]);

  const reactFlowEdges = useMemo(() => {
    return connections.map((conn) => ({
      id: `${conn.from}-${conn.to}`,
      source: conn.from,
      target: conn.to,
      type: 'default',
    }));
  }, [connections]);

  if (!ReactFlow) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-gray-900">
        <div className="text-gray-500">Loading canvas...</div>
      </div>
    );
  }

  return (
    <div style={{ width: '100%', height: '600px' }}>
      <ReactFlow
        nodes={reactFlowNodes}
        edges={reactFlowEdges}
        fitView
        className="bg-gray-900"
        style={{ width: '100%', height: '100%' }}
      >
        {Controls && <Controls />}
        {Background && <Background color="#374151" gap={20} />}
      </ReactFlow>
    </div>
  );
}

export default function SwarmCanvas({ 
  swarmName, 
  nodes, 
  connections, 
  onNodeUpdate, 
  onConnectionUpdate 
}: SwarmCanvasProps) {
  console.log('SwarmCanvas rendered with nodes:', nodes);
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);
  
  return (
    <div className="flex-1 bg-gray-900 relative overflow-hidden">
      {/* Header */}
      <div className="absolute top-4 left-4 z-10">
        <h1 className="text-2xl font-bold text-white">{swarmName}</h1>
      </div>

      {/* ReactFlow Canvas */}
      <div className="w-full h-full" style={{ width: '100%', height: 'calc(100vh - 120px)', minHeight: '400px' }}>
        {isClient ? (
          <ReactFlowCanvas nodes={nodes} connections={connections} />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-gray-900">
            <div className="text-gray-500">Initializing canvas...</div>
          </div>
        )}
      </div>
    </div>
  );
}