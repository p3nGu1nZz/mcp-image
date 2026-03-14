# mcp-image

MCP server that lets AI agents read PNG screenshots, get image metadata (dimensions, size), and receive the raw image data — so the agent can visually analyze what is happening in your game or application.

Communicates over **stdio**, zero runtime dependencies beyond the MCP SDK.

## Tools

| Tool | Description |
|------|-------------|
| `read_image` | Read a PNG file → returns metadata + base64 image for vision analysis |
| `list_images` | List all PNG files in a directory |

## Setup

```bash
npm install
npm run build
```

## VSCode (local install)

Add `.vscode/mcp.json` to your workspace (already included):

```json
{
  "servers": {
    "mcp-image": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/dist/index.js"]
    }
  }
}
```

Open the Command Palette → **MCP: List Servers** to confirm the server is running.

## Usage example (agent prompt)

```
Use the read_image tool with path "/path/to/screenshot.png" to analyze what is
happening visually in the game screenshot.
```
