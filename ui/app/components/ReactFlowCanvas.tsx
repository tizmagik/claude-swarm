import { useState, useCallback, useMemo, useEffect } from "react";
import type { AgentNode, Connection, ReactFlowCanvasProps, AgentEditForm } from "../types/swarm";
import { getLayoutedElements } from "../utils/layout";
import AgentEditModal from "./AgentEditModal";

const nodeWidth = 180;
const nodeHeight = 120;

export default function ReactFlowCanvas({
  nodes,
  connections,
  onNodeUpdate,
  onConnectionUpdate,
  onDeleteNode,
}: ReactFlowCanvasProps) {
  const [ReactFlow, setReactFlow] = useState<any>(null);
  const [Controls, setControls] = useState<any>(null);
  const [Background, setBackground] = useState<any>(null);
  const [localNodes, setLocalNodes] = useState<any[]>([]);
  const [editingNode, setEditingNode] = useState<AgentNode | null>(null);
  const [editForm, setEditForm] = useState<AgentEditForm>({
    name: "",
    model: "",
    tools: [],
    mcps: [],
    description: "",
    directories: [],
  });
  const [reactFlowInstance, setReactFlowInstance] = useState<any>(null);

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
            {node.mcps.length > 0 && (
              <div className="mt-2 space-y-1">
                {node.mcps.slice(0, 3).map((mcp, index) => (
                  <div
                    key={index}
                    className="inline-flex items-center bg-purple-600 text-white text-xs px-2 py-1 rounded-full mx-1"
                    title={`${mcp} - Click node to edit`}
                  >
                    <span className="truncate max-w-[100px]">{mcp}</span>
                  </div>
                ))}
                {node.mcps.length > 3 && (
                  <div className="text-purple-300 text-xs">
                    +{node.mcps.length - 3} more
                  </div>
                )}
              </div>
            )}
          </div>
        ),
      },
      style: {
        background: "linear-gradient(135deg, #334155 0%, #475569 100%)",
        color: "white",
        border: "2px solid #64748b",
        borderRadius: "12px",
        padding: "12px",
        width: `${nodeWidth}px`,
        height: "auto",
        minHeight: `${nodeHeight}px`,
        boxShadow: "0 4px 12px rgba(0, 0, 0, 0.3)",
      },
    }));

    // Only update localNodes if this is a new set of nodes (different IDs or count)
    // Don't overwrite if it's just position changes from drag operations
    setLocalNodes((currentLocalNodes) => {
      if (
        currentLocalNodes.length !== newReactFlowNodes.length ||
        !currentLocalNodes.every(
          (localNode, index) => localNode.id === newReactFlowNodes[index]?.id
        )
      ) {
        return newReactFlowNodes;
      }
      // Update node data but preserve current positions (which may be from drag operations)
      return currentLocalNodes.map((localNode) => {
        const parentNode = newReactFlowNodes.find((n) => n.id === localNode.id);
        return parentNode
          ? { ...parentNode, position: localNode.position }
          : localNode;
      });
    });
  }, [nodes]);

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

  const handleMcpAddToForm = useCallback(
    (mcp: string) => {
      if (mcp && !editForm.mcps.includes(mcp)) {
        setEditForm((prev) => ({
          ...prev,
          mcps: [...prev.mcps, mcp],
        }));
      }
    },
    [editForm.mcps]
  );

  // Auto-layout when nodes or connections change
  useEffect(() => {
    if (
      localNodes.length > 0 &&
      reactFlowEdges.length >= 0 &&
      reactFlowInstance
    ) {
      const applyAutoLayout = async () => {
        try {
          const { nodes: layoutedNodes } = await getLayoutedElements(
            localNodes,
            reactFlowEdges,
            "TB" // Always use vertical layout
          );

          setLocalNodes([...layoutedNodes]);

          // Update parent component with new positions
          const updatedNodes = nodes.map((n) => {
            const layoutedNode = layoutedNodes.find((ln) => ln.id === n.id);
            return layoutedNode
              ? { ...n, x: layoutedNode.position.x, y: layoutedNode.position.y }
              : n;
          });
          onNodeUpdate(updatedNodes);

          // Center the view after layout
          setTimeout(() => {
            reactFlowInstance.fitView({ padding: 0.2, duration: 800 });
          }, 100);
        } catch (error) {
          console.error("Auto-layout failed:", error);
        }
      };

      applyAutoLayout();
    }
  }, [localNodes.length, reactFlowEdges.length, reactFlowInstance]);

  const onConnect = useCallback(
    (connection: any) => {
      const newConnection: Connection = {
        from: connection.source,
        to: connection.target,
      };

      // Add to connections array
      const updatedConnections = [...connections, newConnection];
      onConnectionUpdate(updatedConnections);

      // Update the source node's connections array
      const updatedNodes = nodes.map((node) => {
        if (node.id === connection.source) {
          return {
            ...node,
            connections: [...new Set([...node.connections, connection.target])],
          };
        }
        return node;
      });
      onNodeUpdate(updatedNodes);

      console.log("Created connection:", newConnection);
    },
    [connections, nodes, onConnectionUpdate, onNodeUpdate]
  );

  const onNodeClick = useCallback(
    (_event: any, node: any) => {
      const agentNode = nodes.find((n) => n.id === node.id);
      if (agentNode) {
        setEditingNode(agentNode);
        setEditForm({
          name: agentNode.name,
          model: agentNode.model,
          tools: [...agentNode.tools],
          mcps: [...agentNode.mcps],
          description: agentNode.description,
          directories: Array.isArray(agentNode.directory) ? [...agentNode.directory] : [agentNode.directory],
        });
      }
    },
    [nodes]
  );

  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  }, []);

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();

      try {
        const dragData = JSON.parse(
          event.dataTransfer.getData("application/json")
        );
        console.log("Drop event:", dragData);

        if (dragData.type === "agent") {
          // Create new agent from template
          const clientX = event.clientX;
          const clientY = event.clientY;
          const reactFlowBounds = (event.target as HTMLElement)
            .closest(".react-flow")
            ?.getBoundingClientRect();

          if (reactFlowBounds && reactFlowInstance) {
            const position = reactFlowInstance.screenToFlowPosition({
              x: clientX - reactFlowBounds.left,
              y: clientY - reactFlowBounds.top,
            });

            const agent = dragData.item;

            // Generate human-readable ID from agent name
            const baseId = agent.name
              .toLowerCase()
              .replace(/[^a-z0-9\s]/g, "") // Remove special characters
              .replace(/\s+/g, "_") // Replace spaces with underscores
              .replace(/_+/g, "_") // Replace multiple underscores with single
              .replace(/^_|_$/g, ""); // Remove leading/trailing underscores

            // Ensure uniqueness by checking existing node IDs
            let nodeId = baseId;
            let counter = 1;
            while (nodes.some((n) => n.id === nodeId)) {
              nodeId = `${baseId}_${counter}`;
              counter++;
            }

            const newNode: AgentNode = {
              id: nodeId,
              name: agent.name,
              description: agent.description || "A new agent in the swarm",
              x: position.x,
              y: position.y,
              tools: agent.allowed_tools || ["Read", "Edit", "Write"],
              mcps: agent.mcps?.map((mcp: any) => mcp.name) || [],
              model: agent.model || "sonnet",
              connections: [],
              directory: agent.directory || ".",
            };

            const updatedNodes = [...nodes, newNode];
            onNodeUpdate(updatedNodes);
            console.log("Created new agent:", newNode);
          }
        } else if (dragData.type === "mcp") {
          // Get the element that was dropped on
          const dropTarget = event.target as HTMLElement;
          const nodeElement = dropTarget.closest(".react-flow__node");

          if (nodeElement) {
            const nodeId = nodeElement.getAttribute("data-id");
            if (nodeId) {
              // Add MCP to the node
              const updatedNodes = nodes.map((n) =>
                n.id === nodeId
                  ? {
                      ...n,
                      mcps: [...new Set([...n.mcps, dragData.item.name])],
                    }
                  : n
              );

              // If we're editing this node, update the form state instead of the node directly
              if (editingNode && editingNode.id === nodeId) {
                handleMcpAddToForm(dragData.item.name);
                return; // Don't update the node directly, just the form
              }

              console.log("Adding MCP", dragData.item.name, "to node", nodeId);
              onNodeUpdate(updatedNodes);
            }
          }
        }
      } catch (error) {
        console.error("Error parsing drop data:", error);
      }
    },
    [nodes, onNodeUpdate, reactFlowInstance, editingNode, handleMcpAddToForm]
  );

  const onNodesChange = useCallback(
    (changes: any[]) => {
      // Handle position changes
      const positionChanges = changes.filter(
        (change) => change.type === "position" && change.dragging === false
      );

      if (positionChanges.length > 0) {
        // Update local nodes first
        setLocalNodes((currentNodes) => {
          let updatedLocalNodes = [...currentNodes];
          positionChanges.forEach((change) => {
            const nodeIndex = updatedLocalNodes.findIndex(
              (n) => n.id === change.id
            );
            if (nodeIndex !== -1 && change.position) {
              updatedLocalNodes[nodeIndex] = {
                ...updatedLocalNodes[nodeIndex],
                position: change.position,
              };
            }
          });
          return updatedLocalNodes;
        });

        // Update parent component
        const updatedNodes = nodes.map((n) => {
          const positionChange = positionChanges.find(
            (change) => change.id === n.id
          );
          return positionChange && positionChange.position
            ? {
                ...n,
                x: positionChange.position.x,
                y: positionChange.position.y,
              }
            : n;
        });

        onNodeUpdate(updatedNodes);
      } else {
        // Apply other changes to local nodes
        setLocalNodes((currentNodes) => {
          let updatedNodes = [...currentNodes];
          changes.forEach((change) => {
            if (change.type === "position" && change.position) {
              const nodeIndex = updatedNodes.findIndex(
                (n) => n.id === change.id
              );
              if (nodeIndex !== -1) {
                updatedNodes[nodeIndex] = {
                  ...updatedNodes[nodeIndex],
                  position: change.position,
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

  const handleEditSave = useCallback(() => {
    if (!editingNode) return;

    const updatedNodes = nodes.map((n) =>
      n.id === editingNode.id ? { 
        ...n, 
        ...editForm,
        // Convert directories array back to the proper format
        directory: editForm.directories.length === 1 ? editForm.directories[0] : editForm.directories
      } : n
    );

    onNodeUpdate(updatedNodes);
    setEditingNode(null);
  }, [editingNode, editForm, nodes, onNodeUpdate]);

  const handleEditCancel = useCallback(() => {
    setEditingNode(null);
    setEditForm({
      name: "",
      model: "",
      tools: [],
      mcps: [],
      description: "",
      directories: [],
    });
  }, []);

  const handleNodeDelete = useCallback((nodeId: string) => {
    if (onDeleteNode) {
      onDeleteNode(nodeId);
    }
    setEditingNode(null);
  }, [onDeleteNode]);

  if (!ReactFlow) {
    return (
      <div className="w-full h-full flex items-center justify-center bg-gray-900">
        <div className="text-gray-500">Loading canvas...</div>
      </div>
    );
  }

  return (
    <div
      style={{ width: "100%", height: "100%" }}
      onDragOver={onDragOver}
      onDrop={onDrop}
    >
      <ReactFlow
        nodes={localNodes}
        edges={reactFlowEdges}
        onNodesChange={onNodesChange}
        onNodeClick={onNodeClick}
        onConnect={onConnect}
        onInit={setReactFlowInstance}
        fitView
        fitViewOptions={{ padding: 0.2 }}
        className="bg-slate-950"
        style={{ width: "100%", height: "100%" }}
        nodesDraggable={true}
        nodesConnectable={true}
        elementsSelectable={true}
        defaultViewport={{ x: 0, y: 0, zoom: 0.8 }}
        proOptions={{
          hideAttribution: true,
        }}
      >
        {Controls && (
          <Controls
            className="!bg-slate-800 !border-slate-700 rounded-lg"
            style={
              {
                backgroundColor: "#1e293b",
                borderColor: "#475569",
                "--xy-controls-button-background-color": "#334155",
                "--xy-controls-button-background-color-hover": "#475569",
                "--xy-controls-button-color": "#ffffff",
                "--xy-controls-button-color-hover": "#ffffff",
                "--xy-controls-button-border-color": "#475569",
              } as any
            }
          />
        )}
        {Background && <Background color="#1e293b" gap={20} variant="dots" />}
      </ReactFlow>

      <AgentEditModal
        editingNode={editingNode}
        editForm={editForm}
        setEditForm={setEditForm}
        onSave={handleEditSave}
        onCancel={handleEditCancel}
        onDelete={handleNodeDelete}
      />
    </div>
  );
}