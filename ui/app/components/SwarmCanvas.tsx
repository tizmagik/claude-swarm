import { useState, useRef, useCallback } from 'react';

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

export default function SwarmCanvas({ 
  swarmName, 
  nodes, 
  connections, 
  onNodeUpdate, 
  onConnectionUpdate 
}: SwarmCanvasProps) {
  console.log('SwarmCanvas rendered with nodes:', nodes);
  
  return (
    <div className="flex-1 bg-gray-900 relative overflow-hidden">
      {/* Header */}
      <div className="absolute top-4 left-4 z-10">
        <h1 className="text-2xl font-bold text-white">{swarmName}</h1>
      </div>

      {/* Simple Canvas */}
      <div className="w-full h-full relative">
        {/* Agent Nodes */}
        {nodes.map((node) => (
          <div
            key={node.id}
            className="absolute bg-gray-800 border border-gray-600 rounded-lg p-4 w-48 text-white"
            style={{ 
              left: node.x, 
              top: node.y,
              zIndex: 2
            }}
          >
            <div className="font-semibold text-sm mb-2">
              {node.name}
            </div>
            
            <div className="text-gray-300 text-xs mb-3">
              {node.description}
            </div>

            <div className="space-y-2">
              <div>
                <div className="text-gray-400 text-xs font-medium">Tools:</div>
                <div className="flex flex-wrap gap-1 mt-1">
                  {node.tools.slice(0, 3).map((tool) => (
                    <span
                      key={tool}
                      className="bg-blue-600 text-white text-xs px-2 py-1 rounded"
                    >
                      {tool}
                    </span>
                  ))}
                  {node.tools.length > 3 && (
                    <span className="text-gray-400 text-xs">
                      +{node.tools.length - 3} more
                    </span>
                  )}
                </div>
              </div>

              {node.mcps.length > 0 && (
                <div>
                  <div className="text-gray-400 text-xs font-medium">MCPs:</div>
                  <div className="flex flex-wrap gap-1 mt-1">
                    {node.mcps.slice(0, 2).map((mcp) => (
                      <span
                        key={mcp}
                        className="bg-purple-600 text-white text-xs px-2 py-1 rounded"
                      >
                        {mcp}
                      </span>
                    ))}
                    {node.mcps.length > 2 && (
                      <span className="text-gray-400 text-xs">
                        +{node.mcps.length - 2} more
                      </span>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>
        ))}

        {/* Drop zone message when empty */}
        {nodes.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="text-gray-500 text-center">
              <div className="text-xl mb-2">🎯</div>
              <div>Select a swarm from the sidebar to see agents</div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}