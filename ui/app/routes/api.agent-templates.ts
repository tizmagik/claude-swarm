import type { Route } from "./+types/api.agent-templates";
import fs from 'fs-extra';
import path from 'path';

interface AgentTemplate {
  id: string;
  name: string;
  description: string;
  model?: string;
  prompt?: string;
  allowed_tools?: string[];
  disallowed_tools?: string[];
  mcps?: Array<{
    name: string;
    type: 'stdio' | 'sse';
    command?: string;
    args?: string[];
    url?: string;
  }>;
}

// GET /api/agent-templates - List all agent templates
export async function loader({ request }: Route.LoaderArgs) {
  try {
    const templatesPath = path.join(process.cwd(), '../data/agent-templates.json');
    let templates: AgentTemplate[] = [];
    if (await fs.pathExists(templatesPath)) {
      templates = await fs.readJson(templatesPath);
    }
    return Response.json(templates);
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// POST /api/agent-templates - Create new agent template
export async function action({ request }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  try {
    const templatesPath = path.join(process.cwd(), '../data/agent-templates.json');
    await fs.ensureDir(path.dirname(templatesPath));
    
    let templates: AgentTemplate[] = [];
    if (await fs.pathExists(templatesPath)) {
      templates = await fs.readJson(templatesPath);
    }
    
    const newTemplate = await request.json();
    templates.push(newTemplate);
    await fs.writeJson(templatesPath, templates, { spaces: 2 });
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}