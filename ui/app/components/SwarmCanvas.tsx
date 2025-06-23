import { useState, useEffect } from "react";
import { Zap } from "lucide-react";
import type { SwarmCanvasProps } from "../types/swarm";
import SwarmCanvasHeader from "./SwarmCanvasHeader";
import ReactFlowCanvas from "./ReactFlowCanvas";


export default function SwarmCanvas({
  swarmName,
  nodes,
  connections,
  onNodeUpdate,
  onConnectionUpdate,
  onDeleteNode,
  onSwarmNameUpdate,
}: SwarmCanvasProps) {
  console.log("SwarmCanvas rendered with nodes:", nodes);
  const [isClient, setIsClient] = useState(false);

  useEffect(() => {
    setIsClient(true);
  }, []);

  return (
    <div
      className="flex-1 bg-slate-950 relative overflow-hidden"
      style={{ height: "100%" }}
    >
      <SwarmCanvasHeader
        swarmName={swarmName}
        nodes={nodes}
        connections={connections}
        onSwarmNameUpdate={onSwarmNameUpdate}
      />

      {/* ReactFlow Canvas */}
      <div
        className="absolute w-full"
        style={{
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          height: "calc(100% - 0px)",
        }}
      >
        {isClient ? (
          <ReactFlowCanvas
            nodes={nodes}
            connections={connections}
            onNodeUpdate={onNodeUpdate}
            onConnectionUpdate={onConnectionUpdate}
            onDeleteNode={onDeleteNode}
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
