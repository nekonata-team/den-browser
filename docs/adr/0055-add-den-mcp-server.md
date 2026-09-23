---
status: accepted
---

# Add a Local MCP Server for Den

## Context and Problem

ADR-0047 avoided MCP when the CLI had a narrow operation surface. The CLI now covers common Den, Sheet, Drawer, and Terminal operations through typed IPC, which MCP can expose as discoverable tools with JSON Schema arguments. The [2026-07-28 protocol update](https://blog.modelcontextprotocol.io/posts/2026-07-28/) also supports stateless Streamable HTTP, though v1 only needs local access.

## Decision

- Add a local stdio server as `den mcp`, connected to Den through its existing user-scoped Unix socket.
- Implement an MCP adapter over typed IPC; do not shell out to the CLI or duplicate browser behavior.
- Expose action-first tools with JSON Schema arguments. Keep the v1 catalog, including `inspect_den`, in [`docs/mcp.md`](../mcp.md).
- Resolve targets independently for each call, using explicit IDs before the CLI's documented defaults. Invalid explicit targets fail without fallback.
- Do not open a network listener in v1.

## Considered Options

- **CLI only:** does not give MCP clients discoverable, schema-described tools.
- **Remote HTTP in v1:** deferred until remote access is needed.
- **Shell out to `den`:** rejected in favor of calling the same typed IPC operations directly.

## Consequences

MCP clients can discover and invoke Den operations without CLI syntax. The tool catalog and typed IPC must stay aligned; Den continues to own all live browser and Terminal state.

ADR-0055 supersedes only ADR-0047's MCP-avoidance decision. Its CLI and Unix socket decisions remain accepted.
