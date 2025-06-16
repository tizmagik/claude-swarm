import type { Route } from "./+types/api.swarms.$filename";
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { parse, stringify } from 'yaml';

// GET /api/swarms/:filename - Get specific swarm
export async function loader({ params }: Route.LoaderArgs) {
  try {
    const { filename } = params;
    if (!filename) {
      return Response.json({ error: 'Filename is required' }, { status: 400 });
    }

    const baseDir = path.resolve(process.cwd(), '../');
    const content = await readFile(path.join(baseDir, filename), 'utf8');
    const config = parse(content);
    return Response.json(config);
  } catch (error: any) {
    if (error.code === 'ENOENT') {
      return Response.json({ error: 'Swarm not found' }, { status: 404 });
    }
    return Response.json({ error: error.message }, { status: 500 });
  }
}

// PUT /api/swarms/:filename - Update specific swarm
export async function action({ params, request }: Route.ActionArgs) {
  if (request.method !== 'PUT') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  try {
    const { filename } = params;
    if (!filename) {
      return Response.json({ error: 'Filename is required' }, { status: 400 });
    }

    const { config } = await request.json();
    const baseDir = path.resolve(process.cwd(), '../');
    const yamlContent = stringify(config);
    await writeFile(path.join(baseDir, filename), yamlContent);
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}