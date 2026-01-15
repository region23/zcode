# zcode - Coding Agent with Rich TUI

A modern coding agent written in Zig with a rich terminal user interface powered by libvaxis.

## Features

- **Dual-Mode System**: Plan mode (read-only) and Build mode (full file editing)
- **Multi-Provider Support**: OpenAI, Anthropic Claude, z.ai, DeepSeek, Qwen, OpenRouter (Phases 2+)
- **Rich TUI**: Beautiful terminal interface with libvaxis
- **Tool System**: read_file, list_files, edit_file
- **Streaming Responses**: Real-time LLM responses (Phase 2)
- **Syntax Highlighting**: Code highlighting in responses (Phase 5)

## Installation

### Prerequisites

- Zig 0.13.0 or later
- At least one LLM API key

### Build

```bash
# Fetch dependencies (updates build.zig.zon hash)
zig fetch --save git+https://github.com/rockorager/libvaxis

# Build
zig build

# Run
zig build run
```

## Configuration

zcode loads configuration from environment variables:

```bash
# Required: At least one API key
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export ZAI_API_KEY="..."

# Optional: Override defaults
export ZCODE_DEFAULT_PROVIDER="openai"  # openai, anthropic, etc.
export ZCODE_DEFAULT_MODE="build"       # plan or build
```

## Usage

### Keyboard Shortcuts

- **Tab**: Switch between Plan and Build modes
- **Ctrl+P**: Open provider/model selection (Phase 4)
- **Ctrl+C**: Clear conversation
- **Ctrl+Q**: Quit
- **Enter**: Submit message
- **Backspace**: Delete character

### Modes

**Plan Mode** (`[PLAN]`):
- Read-only mode for analyzing and planning
- Available tools: `read_file`, `list_files`
- Useful for: "Analyze this codebase", "What pattern should I use?"

**Build Mode** (`[BUILD]`):
- Full access mode for making changes
- Available tools: `read_file`, `list_files`, `edit_file`
- Useful for: "Create a new file", "Fix this bug"

### Example Workflow

1. Start in Build mode
2. Ask: "Can you read the src/main.zig file?"
3. Agent uses `read_file` tool to fetch content
4. Ask: "Add error handling to the main function"
5. Agent uses `edit_file` tool to make changes
6. Switch to Plan mode with Tab
7. Ask: "What other improvements can be made?"
8. Agent analyzes without modifying files

## Tools

### read_file
Reads the full content of a file.

```
tool: read_file({"filename": "src/main.zig"})
```

### list_files
Lists files in a directory.

```
tool: list_files({"path": "."})
```

### edit_file
Replaces text in a file or creates a new file.

```
tool: edit_file({
  "path": "test.txt",
  "old_str": "old content",
  "new_str": "new content"
})
```

To create a new file, use empty `old_str`:

```
tool: edit_file({
  "path": "new_file.txt",
  "old_str": "",
  "new_str": "file content"
})
```

## Architecture

```
src/
├── main.zig              # Entry point, event loop
├── app.zig               # Application state
├── config.zig            # Configuration loading
├── parser.zig            # Tool invocation parser
├── api/
│   ├── client.zig        # API client interface
│   ├── common.zig        # Message, Conversation types
│   ├── openai.zig        # OpenAI implementation
│   └── streaming.zig     # SSE parser (Phase 2)
├── tools/
│   ├── registry.zig      # Tool registry
│   ├── read_file.zig     # Read file tool
│   ├── list_files.zig    # List files tool
│   └── edit_file.zig     # Edit file tool
└── ui/
    ├── layout.zig        # Layout manager
    ├── status_bar.zig    # Status bar component
    ├── chat_view.zig     # Chat display
    └── input_view.zig    # Input field
```

## Development Status

- [x] Phase 1: Foundation with TUI (OpenAI, Build mode)
- [ ] Phase 2: Multi-Provider Support with Streaming
- [ ] Phase 3: Dual-Mode System
- [ ] Phase 4: Model Selection Modal
- [ ] Phase 5: Enhanced Features (Syntax highlighting, scrolling)
- [ ] Phase 6: Testing & Documentation

## Testing

```bash
# Run tests
zig build test
```

## License

See LICENSE file.

## Contributing

Contributions welcome! See CONTRIBUTING.md for guidelines.
