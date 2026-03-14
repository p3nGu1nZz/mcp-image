#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { readFileSync, statSync, existsSync, readdirSync } from "fs";
import { resolve, extname } from "path";

/** Read PNG header bytes to extract width and height without extra dependencies. */
function pngDimensions(buf: Buffer): { width: number; height: number } | null {
  const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buf.length < 24 || !buf.subarray(0, 8).equals(PNG_SIG)) return null;
  return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

const DEFAULT_MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB

function getMaxImageBytes(): number {
  const raw = process.env.MCP_IMAGE_MAX_BYTES;
  if (!raw) return DEFAULT_MAX_IMAGE_BYTES;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return DEFAULT_MAX_IMAGE_BYTES;
  }
  return parsed;
}

const server = new Server(
  { name: "mcp-image", version: "1.0.0" },
  { capabilities: { tools: {} } },
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "read_image",
      description:
        "Read a PNG image file and return its metadata and base64 content so an AI agent can visually analyze it.",
      inputSchema: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Absolute or relative path to the PNG file.",
          },
        },
        required: ["path"],
      },
    },
    {
      name: "list_images",
      description: "List all PNG files in a directory.",
      inputSchema: {
        type: "object",
        properties: {
          directory: {
            type: "string",
            description: "Directory path to search for PNG files.",
          },
        },
        required: ["directory"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "read_image") {
    if (!args?.path || typeof args.path !== "string") {
      return {
        content: [{ type: "text", text: "Error: 'path' argument is required." }],
        isError: true,
      };
    }
    const filePath = resolve(args.path);

    if (!existsSync(filePath)) {
      return {
        content: [{ type: "text", text: `Error: file not found: ${filePath}` }],
        isError: true,
      };
    }

    const stats = statSync(filePath);
    const maxBytes = getMaxImageBytes();
    if (stats.size > maxBytes) {
      const sizeMb = (stats.size / (1024 * 1024)).toFixed(2);
      const maxMb = (maxBytes / (1024 * 1024)).toFixed(2);
      return {
        content: [
          {
            type: "text",
            text: `Error: file is too large (${sizeMb} MB). Maximum allowed size is ${maxMb} MB. You can configure this limit via the MCP_IMAGE_MAX_BYTES environment variable.`,
          },
        ],
        isError: true,
      };
    }

    const buf = readFileSync(filePath);
    const dim = pngDimensions(buf);

    if (!dim) {
      return {
        content: [
          {
            type: "text",
            text: "Error: File is not a valid PNG or is truncated/corrupted.",
          },
        ],
        isError: true,
      };
    }

    const metadata = [
      `path: ${filePath}`,
      `size: ${(stats.size / 1024).toFixed(2)} KB`,
      dim ? `dimensions: ${dim.width}x${dim.height}` : null,
      `format: PNG`,
    ]
      .filter(Boolean)
      .join("\n");

    return {
      content: [
        { type: "text", text: metadata },
        { type: "image", data: buf.toString("base64"), mimeType: "image/png" },
      ],
    };
  }

  if (name === "list_images") {
    if (!args?.directory || typeof args.directory !== "string") {
      return {
        content: [{ type: "text", text: "Error: 'directory' argument is required." }],
        isError: true,
      };
    }
    const dir = resolve(args.directory);

    if (!existsSync(dir)) {
      return {
        content: [{ type: "text", text: `Error: directory not found: ${dir}` }],
        isError: true,
      };
    }

    const files = readdirSync(dir, { withFileTypes: true })
      .filter((e) => e.isFile() && extname(e.name).toLowerCase() === ".png")
      .map((e) => resolve(dir, e.name));

    return {
      content: [
        {
          type: "text",
          text: files.length > 0 ? files.join("\n") : "No PNG files found.",
        },
      ],
    };
  }

  return {
    content: [{ type: "text", text: `Unknown tool: ${name}` }],
    isError: true,
  };
});

const transport = new StdioServerTransport();
await server.connect(transport);
