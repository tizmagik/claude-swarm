import { useState, useCallback, useMemo, useEffect } from "react";
import { Zap, Users, ArrowRight } from "lucide-react";

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
  connections,
  onNodeUpdate,
}: {
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
}) {
  const [ReactFlow, setReactFlow] = useState<any>(null);
  const [Controls, setControls] = useState<any>(null);
  const [Background, setBackground] = useState<any>(null);
  const [localNodes, setLocalNodes] = useState<any[]>([]);
  useEffect(() => {
    // Import ReactFlow only on client-side
    import("@xyflow/react").then((module) => {
      setReactFlow(() => module.ReactFlow);
      setControls(() => module.Controls);
      setBackground(() => module.Background);
    });
    // Import ReactFlow styles
    import("@xyflow/react/dist/style.css");
  }, []);

  // Convert nodes to ReactFlow format and update local state when nodes change
  useEffect(() => {
    const newReactFlowNodes = nodes.map((node) => ({
      id: node.id,
      type: "default",
      position: { x: node.x, y: node.y },
      data: {
        label: (
          <div className="text-center">
            <div className="text-white font-semibold text-sm mb-1">
              {node.name}
            </div>
            <div className="text-slate-100 text-xs">{node.model}</div>
            <div className="text-slate-200 text-xs mt-1">
              {node.tools.length} tools
            </div>
          </div>
        ),
      },
      style: {
        background: "linear-gradient(135deg, #334155 0%, #475569 100%)",
        color: "white",
        border: "2px solid #64748b",
        borderRadius: "12px",
        padding: "12px",
        width: "160px",
        height: "80px",
        boxShadow: "0 4px 12px rgba(0, 0, 0, 0.3)",
      },
    }));
    
    // Only update localNodes if this is a new set of nodes (different IDs or count)
    // Don't overwrite if it's just position changes from drag operations
    setLocalNodes(currentLocalNodes => {
      if (currentLocalNodes.length !== newReactFlowNodes.length ||
          !currentLocalNodes.every((localNode, index) => localNode.id === newReactFlowNodes[index]?.id)) {
        return newReactFlowNodes;
      }
      // Update node data but preserve current positions (which may be from drag operations)
      return currentLocalNodes.map(localNode => {
        const parentNode = newReactFlowNodes.find(n => n.id === localNode.id);
        return parentNode ? { ...parentNode, position: localNode.position } : localNode;
      });
    });
  }, [nodes]);


  const onNodesChange = useCallback(
    (changes: any[]) => {
      // Handle position changes
      const positionChanges = changes.filter(change => change.type === 'position' && change.dragging === false);
      
      if (positionChanges.length > 0) {
        // Update local nodes first
        setLocalNodes(currentNodes => {
          let updatedLocalNodes = [...currentNodes];
          positionChanges.forEach(change => {
            const nodeIndex = updatedLocalNodes.findIndex(n => n.id === change.id);
            if (nodeIndex !== -1 && change.position) {
              updatedLocalNodes[nodeIndex] = {
                ...updatedLocalNodes[nodeIndex],
                position: change.position
              };
            }
          });
          return updatedLocalNodes;
        });
        
        // Update parent component
        const updatedNodes = nodes.map(n => {
          const positionChange = positionChanges.find(change => change.id === n.id);
          return positionChange && positionChange.position
            ? { ...n, x: positionChange.position.x, y: positionChange.position.y }
            : n;
        });
        
        onNodeUpdate(updatedNodes);
      } else {
        // Apply other changes to local nodes
        setLocalNodes(currentNodes => {
          let updatedNodes = [...currentNodes];
          changes.forEach(change => {
            if (change.type === 'position' && change.position) {
              const nodeIndex = updatedNodes.findIndex(n => n.id === change.id);
              if (nodeIndex !== -1) {
                updatedNodes[nodeIndex] = {
                  ...updatedNodes[nodeIndex],
                  position: change.position
                };
              }
            }
          });
          return updatedNodes;
        });
      }
    },
    [nodes, onNodeUpdate]
  );

  const reactFlowEdges = useMemo(() => {
    return connections.map((conn) => ({
      id: `${conn.from}-${conn.to}`,
      source: conn.from,
      target: conn.to,
      type: "smoothstep",
      style: {
        stroke: "#64748b",
        strokeWidth: 2,
      },
      markerEnd: {
        type: "arrowclosed",
        color: "#64748b",
      },
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
    <div style={{ width: "100%", height: "100%" }}>
      <ReactFlow
        nodes={localNodes}
        edges={reactFlowEdges}
        onNodesChange={onNodesChange}
        fitView
        fitViewOptions={{ padding: 0.2 }}
        className="bg-slate-950"
        style={{ width: "100%", height: "100%" }}
        nodesDraggable={true}
        nodesConnectable={true}
        elementsSelectable={true}
        defaultViewport={{ x: 0, y: 0, zoom: 0.8 }}
      >
        {Controls && (
          <Controls className="bg-slate-800 border border-slate-700 rounded-lg" />
        )}
        {Background && <Background color="#1e293b" gap={20} variant="dots" />}
      </ReactFlow>
    </div>
  );
}

export default function SwarmCanvas({
  swarmName,
  nodes,
  connections,
  onNodeUpdate,
}: SwarmCanvasProps) {
  console.log("SwarmCanvas rendered with nodes:", nodes);
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  return (
    <div className="flex-1 bg-slate-950 relative overflow-hidden" style={{ height: '100%' }}>
      {/* Header */}
      <div className="absolute top-4 left-4 lg:top-6 lg:left-6 z-10 bg-slate-900/90 backdrop-blur-sm rounded-xl px-4 py-3 lg:px-6 border border-slate-700 max-w-sm lg:max-w-none">
        <h1 className="text-lg lg:text-2xl font-bold text-white flex items-center">
          <Zap className="w-5 h-5 lg:w-6 lg:h-6 mr-2 lg:mr-3 text-blue-400" />
          <span className="truncate">{swarmName}</span>
        </h1>
        <div className="text-slate-400 text-xs lg:text-sm mt-1 flex items-center">
          <Users className="w-3 h-3 mr-1" />
          {nodes.length} agents
          <ArrowRight className="w-3 h-3 mx-2" />
          {connections.length} connections
        </div>
      </div>

      {/* ReactFlow Canvas */}
      <div 
        className="absolute w-full" 
        style={{
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          height: 'calc(100% - 0px)'
        }}
      >
        {isClient ? (
          <ReactFlowCanvas
            nodes={nodes}
            connections={connections}
            onNodeUpdate={onNodeUpdate}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-slate-950">
            <div className="text-center">
              <Zap className="w-12 h-12 mx-auto animate-pulse text-blue-400 mb-4" />
              <div className="text-slate-400 text-base lg:text-lg">
                Initializing canvas...
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
