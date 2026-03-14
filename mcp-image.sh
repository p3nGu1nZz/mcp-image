#!/usr/bin/env sh
# mcp-image: MCP stdio server for reading and analyzing PNG images.
# Requires: python3 (stdlib only, no extra packages).
# Usage:    sh mcp-image.sh
set -e
TMP=$(mktemp /tmp/mcp_image_XXXXXX.py)
trap 'rm -f "$TMP"' EXIT INT TERM
cat > "$TMP" << 'PYEOF'
import asyncio, base64, json, os, struct, sys

# ── constants ──────────────────────────────────────────────────────────────────
MAX_BYTES = 20 * 1024 * 1024  # 20 MB hard limit per image
PNG_SIG   = b'\x89PNG\r\n\x1a\n'

# ── PNG helpers (stdlib only) ──────────────────────────────────────────────────
def png_dimensions(data: bytes):
    """Return (w, h) from PNG IHDR, or None if not a valid PNG."""
    if len(data) < 24 or data[:8] != PNG_SIG:
        return None
    w = struct.unpack_from('>I', data, 16)[0]
    h = struct.unpack_from('>I', data, 20)[0]
    return w, h

# ── JSON-RPC helpers ───────────────────────────────────────────────────────────
def _write(obj: dict) -> None:
    line = json.dumps(obj, separators=(',', ':'))
    sys.stdout.write(line + '\n')
    sys.stdout.flush()

def ok(req_id, content):
    _write({"jsonrpc": "2.0", "id": req_id, "result": {"content": content}})

def err(req_id, text):
    _write({"jsonrpc": "2.0", "id": req_id,
            "result": {"content": [{"type": "text", "text": text}], "isError": True}})

# ── tool implementations ───────────────────────────────────────────────────────
def handle_read_image(req_id, args):
    path = args.get("path") if args else None
    if not path or not isinstance(path, str):
        return err(req_id, "Error: 'path' argument is required.")

    fpath = os.path.realpath(path)
    try:
        st = os.stat(fpath)
    except OSError as e:
        return err(req_id, f"Error: {e}")

    if not os.path.isfile(fpath):
        return err(req_id, f"Error: not a file: {fpath}")

    if st.st_size > MAX_BYTES:
        return err(req_id, f"Error: file too large ({st.st_size // 1024} KB > {MAX_BYTES // 1024} KB limit).")

    try:
        with open(fpath, 'rb') as f:
            data = f.read()
    except OSError as e:
        return err(req_id, f"Error reading file: {e}")

    dim = png_dimensions(data)
    if dim is None:
        return err(req_id, f"Error: file is not a valid PNG: {fpath}")

    w, h = dim
    meta = f"path: {fpath}\nsize: {st.st_size / 1024:.2f} KB\ndimensions: {w}x{h}\nformat: PNG"
    ok(req_id, [
        {"type": "text", "text": meta},
        {"type": "image", "data": base64.b64encode(data).decode(), "mimeType": "image/png"},
    ])

def handle_list_images(req_id, args):
    directory = args.get("directory") if args else None
    if not directory or not isinstance(directory, str):
        return err(req_id, "Error: 'directory' argument is required.")

    dpath = os.path.realpath(directory)
    try:
        st = os.stat(dpath)
    except OSError as e:
        return err(req_id, f"Error: {e}")

    if not os.path.isdir(dpath):
        return err(req_id, f"Error: not a directory: {dpath}")

    try:
        files = []
        for root, _, names in os.walk(dpath):
            for name in sorted(names):
                if name.lower().endswith('.png'):
                    files.append(os.path.join(root, name))
        files.sort()
    except OSError as e:
        return err(req_id, f"Error walking directory: {e}")

    text = '\n'.join(files) if files else "No PNG files found."
    ok(req_id, [{"type": "text", "text": text}])

# ── MCP tool definitions ───────────────────────────────────────────────────────
TOOLS = [
    {
        "name": "read_image",
        "description": (
            "Read a PNG file and return its metadata and base64 content "
            "so an AI agent can visually analyze it."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute or relative path to the PNG file."}
            },
            "required": ["path"],
        },
    },
    {
        "name": "list_images",
        "description": "Recursively list all PNG files under a directory.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "directory": {"type": "string", "description": "Directory to search for PNG files."}
            },
            "required": ["directory"],
        },
    },
]

# ── request dispatcher ─────────────────────────────────────────────────────────
def dispatch(msg: dict) -> None:
    method  = msg.get("method", "")
    req_id  = msg.get("id")
    params  = msg.get("params") or {}

    if method == "initialize":
        _write({"jsonrpc": "2.0", "id": req_id, "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "mcp-image", "version": "1.0.0"},
        }})
    elif method == "tools/list":
        _write({"jsonrpc": "2.0", "id": req_id, "result": {"tools": TOOLS}})
    elif method == "tools/call":
        name = params.get("name")
        args = params.get("arguments")
        if name == "read_image":
            handle_read_image(req_id, args)
        elif name == "list_images":
            handle_list_images(req_id, args)
        else:
            err(req_id, f"Unknown tool: {name}")
    elif method in ("notifications/initialized",):
        pass  # notifications need no response
    elif req_id is not None:
        _write({"jsonrpc": "2.0", "id": req_id,
                "error": {"code": -32601, "message": f"Method not found: {method}"}})

# ── main event loop ────────────────────────────────────────────────────────────
async def main():
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)

    while True:
        try:
            line = await reader.readline()
        except Exception:
            break
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            dispatch(msg)
        except Exception as e:
            req_id = msg.get("id")
            if req_id is not None:
                err(req_id, f"Internal error: {e}")

asyncio.run(main())
PYEOF
command -v python3 > /dev/null 2>&1 || { echo "Error: python3 not found in PATH" >&2; exit 1; }
exec python3 "$TMP"
