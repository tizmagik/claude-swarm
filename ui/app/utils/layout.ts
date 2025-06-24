// Layout utilities for React Flow canvas using dagre

// Automatic layout using dagre - dynamic import for client-side
export const getLayoutedElements = async (
  nodes: any[],
  edges: any[],
  direction = "TB"
) => {
  const dagre = await import("@dagrejs/dagre");
  const dagreGraph = new dagre.graphlib.Graph();
  dagreGraph.setDefaultEdgeLabel(() => ({}));

  const isHorizontal = direction === "LR";
  dagreGraph.setGraph({ rankdir: direction });

  nodes.forEach((node) => {
    dagreGraph.setNode(node.id, { width: 180, height: 120 }); // Using constants
  });

  edges.forEach((edge) => {
    dagreGraph.setEdge(edge.source, edge.target);
  });

  dagre.layout(dagreGraph);

  nodes.forEach((node) => {
    const nodeWithPosition = dagreGraph.node(node.id);
    node.targetPosition = isHorizontal ? "left" : "top";
    node.sourcePosition = isHorizontal ? "right" : "bottom";

    // We are shifting the dagre node position (anchor=center center) to the top left
    // so it matches the React Flow node anchor point (top left).
    node.position = {
      x: nodeWithPosition.x - 180 / 2, // Using NODE_WIDTH constant
      y: nodeWithPosition.y - 120 / 2, // Using NODE_HEIGHT constant
    };

    return node;
  });

  return { nodes, edges };
};