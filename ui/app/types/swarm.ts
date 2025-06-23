// Shared types for the Swarm UI components

export interface AgentNode {
  id: string;
  name: string;
  description: string;
  x: number;
  y: number;
  tools: string[];
  mcps: string[];
  model: string;
  connections: string[];
  directory: string | string[]; // Support both single directory and array of directories
}

export interface Connection {
  from: string;
  to: string;
}

export interface SwarmCanvasProps {
  swarmName: string;
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
  onConnectionUpdate: (connections: Connection[]) => void;
  onDeleteNode?: (nodeId: string) => void;
  onSwarmNameUpdate?: (newName: string) => void;
}

export interface AgentEditForm {
  name: string;
  model: string;
  tools: string[];
  mcps: string[];
  description: string;
  directories: string[]; // Array of directories for multi-directory support
}

export interface ReactFlowCanvasProps {
  nodes: AgentNode[];
  connections: Connection[];
  onNodeUpdate: (nodes: AgentNode[]) => void;
  onConnectionUpdate: (connections: Connection[]) => void;
  onDeleteNode?: (nodeId: string) => void;
}

// Constants
export const NODE_WIDTH = 180;
export const NODE_HEIGHT = 120;