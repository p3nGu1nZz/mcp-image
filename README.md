# mcp-image

MCP stdio server that lets AI agents read PNG screenshots, inspect metadata (path, size, dimensions), and receive the raw image for visual analysis — useful for debugging game playtests.

**Single file. Python stdlib only. No packages to install.**

## Requirements

- Python 3.8+
- A vision-capable LLM client (e.g. GitHub Copilot Agent, Claude)

## Tools

| Tool | Input | Description |
|------|-------|-------------|
| `read_image` | `path` (string) | Read a PNG → returns metadata + base64 image |
| `list_images` | `directory` (string) | Recursively list all PNG files under a directory |

## VSCode (local install)

`.vscode/mcp.json` is already included:

```json
{
  "servers": {
    "mcp-image": {
      "type": "stdio",
      "command": "sh",
      "args": ["${workspaceFolder}/mcp-image.sh"]
    }
  }
}
```

Open the Command Palette → **MCP: List Servers** to confirm the server is running.  
No build step required — just open the workspace.

## CLI test

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_image","arguments":{"path":"/path/to/screenshot.png"}}}\n' \
  | sh mcp-image.sh
```

## Notes

- Files larger than 20 MB are rejected.
- Only valid PNG files (correct signature + IHDR) are accepted.
- `list_images` walks subdirectories recursively.
