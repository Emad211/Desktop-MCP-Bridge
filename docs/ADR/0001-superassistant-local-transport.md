# ADR 0001 — SuperAssistant local transport

- Status: Accepted
- Decision date: 2026-08-01
- Applies to: Desktop MCP Bridge v2 normal ChatGPT web path

## Context

The project already exposes a complete stdio MCP server and a separate HTTPS GPT Action gateway. The v2 objective is to use the normal ChatGPT web interface and its normal account usage rather than OpenAI API inference or the Codex backend.

MCP SuperAssistant provides a browser extension that detects MCP tool calls in ChatGPT web, executes them through a localhost proxy, and inserts results back into the same conversation. Its official proxy accepts stdio MCP child servers and exposes SSE, Streamable HTTP, or WebSocket endpoints.

The extension currently has open compatibility reports around Streamable HTTP tool loading, output schemas in `tools/list`, ChatGPT rendering, and automatic execution. The initial delivery therefore needs a conservative compatibility path and explicit diagnostics.

## Decision

1. Desktop MCP Bridge remains the authority for Windows capabilities.
2. The SuperAssistant proxy launches a dedicated Desktop MCP Bridge stdio entry point.
3. The dedicated entry point suppresses structured output schemas for extension compatibility while the standard MCP entry point remains unchanged.
4. The extension-facing transport is SSE at `http://localhost:3006/sse` for the first acceptance gate.
5. The entire path remains on localhost; the normal ChatGPT web path does not require ngrok, Tailscale, Cloudflare, or a public inbound endpoint.
6. Auto-Execute and Auto-Submit remain disabled by default.
7. Start, stop, status, config export, and preflight are owned by this repository rather than undocumented manual commands.
8. The tested extension and proxy versions are recorded in each acceptance report.

## Resulting architecture

```text
ChatGPT web
   |
MCP SuperAssistant browser extension
   |
http://127.0.0.1:3006/sse
   |
@srbhptl39/mcp-superassistant-proxy
   |
Desktop MCP Bridge compatibility entry point over stdio
   |
DesktopBridge runtime
   |
Windows session
```

## Why not connect the extension directly to the existing HTTP MCP server?

The existing server can expose SSE or Streamable HTTP, but the local proxy provides the extension's expected CORS and aggregation behavior, stable endpoint conventions, child process lifecycle, and a documented troubleshooting surface. It also isolates extension-specific compatibility from the standard MCP server.

## Why SSE first?

SSE is the extension's established default path. Streamable HTTP is retained as a selectable experimental mode, but it is not the release-blocking path until tool discovery and response handling are verified against the current extension.

## Security consequences

- No public tunnel is required for this path.
- The proxy must bind only to localhost.
- Full mode still grants broad Windows authority to the child process.
- Manual Run remains the default user checkpoint.
- The bridge audit and kill switch remain authoritative.
- A foreign listener on the configured proxy port must never be terminated automatically.

## Reliability consequences

- Extension changes can still break the browser-side adapter.
- A versioned acceptance record is required.
- Output-schema suppression is an intentionally narrow compatibility measure and must have a contract test.
- The standard MCP path must retain normal structured-output behavior.

## Alternatives considered

### Private Custom GPT Action

Already implemented and useful, but it is not the user's requested normal ChatGPT chat path and requires a public HTTPS endpoint.

### Official ChatGPT local MCP tunnel

Preferred when broadly available to the user's plan, but it is not currently a dependable personal-account local-write path.

### Browser-session reverse engineering

Rejected as the primary architecture because it handles account sessions and is more fragile and policy-sensitive than an explicit browser extension plus MCP tool protocol.

### Direct unrestricted shell server

Rejected because the existing bridge already provides audit, kill switch, profiles, bounded output, semantic browser/UI tools, and process lifecycle controls.

## Upstream references

- MCP SuperAssistant: https://github.com/srbhptl39/MCP-SuperAssistant
- MCP SuperAssistant proxy package: https://www.npmjs.com/package/@srbhptl39/mcp-superassistant-proxy
- MCP Python SDK: https://github.com/modelcontextprotocol/python-sdk
