I want you to build a complete full-stack UI for this open source project (claude-swarm). See the mockup in the `mockup.png` file.

Use the following technology stack and requirements. Read everything carefully before you start coding.
⸻
:wrench: Tech Stack
• Frontend:
• React 18+ (TypeScript)
• TailwindCSS for styling
• ShadCN/UI for components and layout
• react-dnd or similar for drag-and-drop support
• WebSockets for persistent, bidirectional terminal communication
• Backend:
• Node.js (preferably using Express)
• Manages spawning Claude agents via shell (per claude-swarm)
• Exposes WebSocket server for command streaming
• Keeps persistent agent/terminal mapping across client refreshes
• Deployment assumptions:
• Single-user (for now), local deployment
• Runs with Node + pnpm
• Supports hot reload during development (use Vite)
⸻
:brain: High-Level Goals
Build a visual orchestration UI for claude-swarm. The UI should allow the user to:
• Interacts with claude-swarm CLI to spawn and manage agents
• Drag and drop agents/tools into a workflow canvas
• Assign roles or behaviors to agents, these should be editable in the UI
• Agents can be stored as presets and used later (left hand-side panel)
• Claude-swarm workflows can be saved and loaded later (these produce claude-swarm compatible yml files)
• Connect agents/tools visually (like a flowchart)
• View terminal output from claude-swarm CLI (real-time)
• Have all terminal streams reconnect after page refresh (resilient WebSocket design)
⸻
:jigsaw: Detailed Features
Agent Management
• Sidebar Panel listing all available agent templates (read from swarm.yaml)
• User can click/drag to instantiate a new agent instance into the canvas
• Each agent is a draggable “card” or node with:
• Agent name
• Unique ID (UUID)
• Role/command/description (editable inline)
• Status (active, running, error, etc.)
• Terminal output window (real-time, expandable)
• Input field for sending messages/commands to that agent
Workflow Canvas
• A central area (canvas-like UI) to drag-and-drop agents
• Agents can be linked together via arrows/lines to indicate `connections` between agents
• Layout and connections should auto-layout based on a given swarm.yaml file
• Use react-flow or react-dnd to handle the drag/connection UI
Terminal Streaming & Commands
• WebSocket-based communication between frontend and backend
• Each claude-swarm has its own persistent shell session
• Terminal output streams live to the agent’s UI component
• User can send manual commands or prompt messages from the agent card
• Refreshing the page must re-establish the WebSocket and restore session:
• Backend maintains a registry of running agent shells
• Client provides its agent UUIDs on reconnect
• Backend resends last N lines of output
WebSocket Design
• WebSocket opens when frontend loads
• Messages have the format:
{
type: 'spawn' | 'command' | 'output' | 'reconnect',
agentId: string,
data?: string
}
• On client reconnect, frontend sends:
{
type: 'reconnect',
agentIds: [string]
}
• Backend replies with:
{
type: 'output',
agentId: string,
data: '...previous output here...'
}
Agent Spawning
• Use the existing claude-swarm CLI/tooling
• Backend must be able to:
• Spawn agents dynamically
• Route command input to the correct child process
• Stream stdout/stderr to the correct client(s)
• Restart or kill agents as needed
⸻
:art: Styling Requirements
• Use TailwindCSS as the primary styling framework
• Use ShadCN UI components where possible (buttons, modals, cards, tabs)
• UI must be modern, responsive, clean
• Optional light mode support (default dark)
⸻
:receipt: Project Structure
frontend/ (React)
• App.tsx
• components/AgentCard.tsx
• components/Canvas.tsx
• components/Sidebar.tsx
• lib/socket.ts (WebSocket connection manager)
• hooks/useAgents.ts
• Tailwind and ShadCN already set up via Vite
backend/ (Node)
• index.ts (Express app)
• agentManager.ts (spawns and manages child processes)
• websocket.ts (WebSocket server with reconnect logic)
• utils/yamlParser.ts (reads swarm.yaml for agent templates)
⸻
:round_pushpin: Example User Flow
User loads the page
Sidebar shows available Claude agent templates (from swarm.yaml files)
User drags one into the canvas
Backend spawns that agent as a process
Agent card appears with terminal stream inside
User types command, sees real-time output
User links one agent to another visually
Refreshing page retains the agent(s) and session(s)
User can stop an agent, reconfigure its prompt, or move things around
⸻
:white_check_mark: Do Not Include
• Unit or integration tests
• Authentication or multi-user logic
• External database (use flat file persistence via Node backend for now. LocalStorage can be used for any state that needs to persists on the frontend)
• Dockerization (unless needed for local dev convenience)
⸻
:end: Deliverables
At the end of the build, I want:
• A single app/package.json file that can be used to run the UI app locally.
• A working React frontend (app/frontend/). It should be beautiful, easy to use, and functional.
• A working Node backend (app/backend/)
• pnpm dev scripts in both folders for local development
• Full WebSocket integration
• Agent terminal UI with live output
• Drag-and-drop canvas and agent links
• Styling via Tailwind + ShadCN
