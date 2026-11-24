/*
 * Vercel Function entry. Bundled by `npm run build:vercel` into
 * frontend/api/claude-mcp.js and routed by frontend/vercel.json:
 * /mcp, /oauth/*, /.well-known/oauth-* -> /api/claude-mcp?route=...
 */
import { createRemoteHandler } from "./remote/handler.js";

export const config = { maxDuration: 60 };

export default createRemoteHandler();
