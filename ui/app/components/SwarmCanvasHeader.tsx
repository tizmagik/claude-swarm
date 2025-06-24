import { useState, useEffect } from "react";
import { Zap, Users, ArrowRight, Edit3 } from "lucide-react";
import type { AgentNode, Connection } from "../types/swarm";

interface SwarmCanvasHeaderProps {
  swarmName: string;
  nodes: AgentNode[];
  connections: Connection[];
  onSwarmNameUpdate?: (newName: string) => void;
}

export default function SwarmCanvasHeader({
  swarmName,
  nodes,
  connections,
  onSwarmNameUpdate,
}: SwarmCanvasHeaderProps) {
  const [editingSwarmName, setEditingSwarmName] = useState(false);
  const [newSwarmName, setNewSwarmName] = useState(swarmName);

  useEffect(() => {
    setNewSwarmName(swarmName);
  }, [swarmName]);

  return (
    <div className="absolute top-4 left-4 lg:top-6 lg:left-6 z-10 bg-slate-900/90 backdrop-blur-sm rounded-xl px-4 py-3 lg:px-6 border border-slate-700 max-w-sm lg:max-w-none">
      {editingSwarmName ? (
        <div className="flex items-center gap-2">
          <Zap className="w-5 h-5 lg:w-6 lg:h-6 text-blue-400" />
          <input
            type="text"
            value={newSwarmName}
            onChange={(e) => setNewSwarmName(e.target.value)}
            onBlur={() => {
              if (newSwarmName.trim() && newSwarmName !== swarmName && onSwarmNameUpdate) {
                onSwarmNameUpdate(newSwarmName.trim());
              }
              setEditingSwarmName(false);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                if (newSwarmName.trim() && newSwarmName !== swarmName && onSwarmNameUpdate) {
                  onSwarmNameUpdate(newSwarmName.trim());
                }
                setEditingSwarmName(false);
              } else if (e.key === 'Escape') {
                setNewSwarmName(swarmName);
                setEditingSwarmName(false);
              }
            }}
            className="text-lg lg:text-2xl font-bold text-white bg-transparent border-none outline-none flex-1 min-w-0"
            autoFocus
          />
        </div>
      ) : (
        <h1 
          className="text-lg lg:text-2xl font-bold text-white flex items-center cursor-pointer hover:text-blue-100 transition-colors"
          onClick={() => onSwarmNameUpdate && setEditingSwarmName(true)}
          title={onSwarmNameUpdate ? "Click to edit swarm name" : undefined}
        >
          <Zap className="w-5 h-5 lg:w-6 lg:h-6 mr-2 lg:mr-3 text-blue-400" />
          <span className="truncate">{swarmName}</span>
          {onSwarmNameUpdate && (
            <Edit3 className="w-4 h-4 ml-2 text-slate-400 opacity-0 group-hover:opacity-100 transition-opacity" />
          )}
        </h1>
      )}
      <div className="text-slate-400 text-xs lg:text-sm mt-1 flex items-center">
        <Users className="w-3 h-3 mr-1" />
        {nodes.length} agents
        <ArrowRight className="w-3 h-3 mx-2" />
        {connections.length} connections
      </div>
    </div>
  );
}