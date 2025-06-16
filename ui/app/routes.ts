import { type RouteConfig, index, route } from "@react-router/dev/routes";

export default [
  index("routes/home.tsx"),
  route("api/swarms", "routes/api.swarms.ts"),
  route("api/swarms/:filename", "routes/api.swarms.$filename.ts"),
  route("api/agent-templates", "routes/api.agent-templates.ts"),
  route("api/mcp-tools", "routes/api.mcp-tools.ts"),
] satisfies RouteConfig;
