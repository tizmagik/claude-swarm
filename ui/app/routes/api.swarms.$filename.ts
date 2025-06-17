import type { Route } from "./+types/api.swarms.$filename";
import { readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import { parse, stringify } from 'yaml';

interface ExecutionState {
  [key: string]: {
    process?: any;
    status: 'running' | 'stopped' | 'error';
    startTime?: Date;
    logs: string[];
    pid?: number;
    memory?: number;
    cpu?: number;
  };
}

// Store running processes in memory (in production, use Redis or similar)
const executionStates: ExecutionState = {};

// GET /api/swarms/:filename - Get specific swarm
// GET /api/swarms/:filename/execution - Get execution status
export async function loader({ params, request }: Route.LoaderArgs) {
  const { filename } = params;
  if (!filename) {
    return Response.json({ error: 'Filename is required' }, { status: 400 });
  }

  const url = new URL(request.url);
  const isExecutionRequest = url.searchParams.get('action') === 'execution' || url.pathname.endsWith('/execution');

  if (isExecutionRequest) {
    // Handle execution status request
    const state = executionStates[filename];
    
    if (!state) {
      return Response.json({ 
        status: 'stopped',
        logs: [],
        startTime: null
      });
    }

    return Response.json({
      status: state.status,
      logs: state.logs,
      startTime: state.startTime,
      pid: state.pid,
      memory: state.memory,
      cpu: state.cpu,
    });
  }

  // Handle regular swarm config request
  try {
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
// POST /api/swarms/:filename/execution - Control execution
export async function action({ params, request }: Route.ActionArgs) {
  const { filename } = params;
  if (!filename) {
    return Response.json({ error: 'Filename is required' }, { status: 400 });
  }

  const url = new URL(request.url);
  const isExecutionRequest = url.searchParams.get('action') === 'execution' || url.pathname.endsWith('/execution');

  if (isExecutionRequest && request.method === 'POST') {
    // Handle execution control request
    const { action: execAction } = await request.json();

    if (execAction === 'start') {
      return startSwarmExecution(filename);
    } else if (execAction === 'stop') {
      return stopSwarmExecution(filename);
    } else if (execAction === 'restart') {
      await stopSwarmExecution(filename);
      return startSwarmExecution(filename);
    } else if (execAction === 'logs') {
      return getSwarmLogs(filename);
    }

    return Response.json({ error: 'Invalid action' }, { status: 400 });
  }

  if (request.method !== 'PUT') {
    return Response.json({ error: 'Method not allowed' }, { status: 405 });
  }

  // Handle regular swarm config update
  try {
    const { config } = await request.json();
    const baseDir = path.resolve(process.cwd(), '../');
    const yamlContent = stringify(config);
    await writeFile(path.join(baseDir, filename), yamlContent);
    return Response.json({ success: true });
  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function startSwarmExecution(filename: string) {
  try {
    // Stop existing process if running
    if (executionStates[filename]?.process) {
      await stopSwarmExecution(filename);
    }

    const baseDir = path.resolve(process.cwd(), '../');
    const swarmPath = path.join(baseDir, filename);

    // For testing, use a simple echo command that simulates swarm execution
    // In production, this would be: spawn('claude-swarm', [swarmPath])
    const testCommand = process.platform === 'win32' 
      ? spawn('cmd', ['/c', `echo Starting swarm ${filename} && timeout /t 2 && echo Agent 1 starting... && timeout /t 1 && echo Agent 2 connecting... && timeout /t 1 && echo Swarm running successfully && timeout /t 5 && echo Swarm completed`])
      : spawn('sh', ['-c', `echo "Starting swarm ${filename}" && sleep 2 && echo "Agent 1 starting..." && sleep 1 && echo "Agent 2 connecting..." && sleep 1 && echo "Swarm running successfully" && sleep 5 && echo "Swarm completed"`]);

    // Initialize execution state
    executionStates[filename] = {
      process: testCommand,
      status: 'running',
      startTime: new Date(),
      logs: [`Starting execution of ${filename}...`],
      pid: testCommand.pid,
      memory: 0,
      cpu: 0
    };

    // Handle process output
    testCommand.stdout?.on('data', (data: Buffer) => {
      const output = data.toString();
      if (executionStates[filename]) {
        executionStates[filename].logs.push(`[STDOUT] ${output.trim()}`);
      }
    });

    testCommand.stderr?.on('data', (data: Buffer) => {
      const output = data.toString();
      if (executionStates[filename]) {
        executionStates[filename].logs.push(`[STDERR] ${output.trim()}`);
      }
    });

    // Handle process completion
    testCommand.on('close', (code: number | null) => {
      if (executionStates[filename]) {
        executionStates[filename].status = code === 0 ? 'stopped' : 'error';
        executionStates[filename].logs.push(`Process exited with code ${code}`);
        delete executionStates[filename].process;
      }
    });

    testCommand.on('error', (error: Error) => {
      if (executionStates[filename]) {
        executionStates[filename].status = 'error';
        executionStates[filename].logs.push(`[ERROR] ${error.message}`);
        delete executionStates[filename].process;
      }
    });

    return Response.json({ 
      success: true, 
      status: 'running',
      message: `Started execution of ${filename}` 
    });

  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function stopSwarmExecution(filename: string) {
  try {
    const state = executionStates[filename];
    
    if (!state?.process) {
      return Response.json({ 
        success: true, 
        message: 'No running process to stop' 
      });
    }

    // Kill the process
    state.process.kill('SIGTERM');
    
    // Update state
    state.status = 'stopped';
    state.logs.push('Execution stopped by user');
    delete state.process;

    return Response.json({ 
      success: true, 
      status: 'stopped',
      message: `Stopped execution of ${filename}` 
    });

  } catch (error: any) {
    return Response.json({ error: error.message }, { status: 500 });
  }
}

async function getSwarmLogs(filename: string) {
  const state = executionStates[filename];
  
  return Response.json({
    logs: state?.logs || [],
    status: state?.status || 'stopped'
  });
}