import type { Route } from "./+types/api.mcp-tools";
import fs from 'fs-extra';
import path from 'path';

interface McpTool {
  id: string;
  name: string;
  type: 'stdio' | 'sse';
  command?: string;
  args?: string[];
  url?: string;
  description?: string;
}

// GET /api/mcp-tools - List all MCP tools
export async function loader({ request }: Route.LoaderArgs) {
  try {
    const toolsPath = path.join(process.cwd(), '../data/mcp-tools.json');
    let tools: McpTool[] = [];
    if (await fs.pathExists(toolsPath)) {
      tools = await fs.readJson(toolsPath);
    }
    return Response.json(tools);
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// POST /api/mcp-tools - Create new MCP tool
export async function action({ request }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  try {
    const toolsPath = path.join(process.cwd(), '../data/mcp-tools.json');
    await fs.ensureDir(path.dirname(toolsPath));
    
    let tools: McpTool[] = [];
    if (await fs.pathExists(toolsPath)) {
      tools = await fs.readJson(toolsPath);
    }
    
    const newTool = await request.json();
    tools.push(newTool);
    await fs.writeJson(toolsPath, tools, { spaces: 2 });
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}