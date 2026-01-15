# zcode - Coding Agent with Rich TUI

A modern coding agent written in Zig with a rich terminal user interface powered by libvaxis.

## Features

- **Multi-Provider Support**: OpenAI, Anthropic Claude, Z.AI, DeepSeek, Qwen, OpenRouter
- **Dynamic Model Selection**: Ctrl+P modal for switching providers and models
- **Streaming Responses**: Real-time LLM responses with SSE
- **Dual-Mode System**: Plan mode (read-only) and Build mode (full file editing)
- **Rich TUI**: Beautiful terminal interface with libvaxis
- **Tool System**: read_file, list_files, edit_file
- **Syntax Highlighting**: Code blocks highlighted for Zig, Python, JavaScript, JSON
- **Advanced Scrolling**: Page Up/Down, Home/End, arrow keys
- **Error Display**: Color-coded error messages in bold red

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

### Quick Start

1. **Copy the example environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` and add at least one API key:**
   ```bash
   # Example for OpenAI
   export OPENAI_API_KEY="sk-..."

   # Example for Anthropic
   export ANTHROPIC_API_KEY="sk-ant-..."
   ```

3. **Load the environment:**
   ```bash
   source .env
   ```

4. **Run zcode:**
   ```bash
   zig build run
   ```

### Environment Variables

zcode loads configuration from environment variables:

```bash
# Required: At least one API key
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
export ZAI_API_KEY="..."
export DEEPSEEK_API_KEY="..."  # Or use OPENROUTER_API_KEY
export QWEN_API_KEY="..."      # Or use OPENROUTER_API_KEY
export OPENROUTER_API_KEY="sk-or-..."

# Optional: Override defaults
export ZCODE_DEFAULT_PROVIDER="anthropic"  # openai, anthropic, zai, deepseek, qwen, openrouter
export ZCODE_DEFAULT_MODE="build"          # plan or build
```

See `.env.example` for a complete configuration template with all available options.

## Usage

### Keyboard Shortcuts

**Mode & Configuration:**
- **Tab**: Switch between Plan and Build modes
- **Ctrl+P**: Open provider/model selection modal

**Conversation:**
- **Enter**: Submit message
- **Backspace**: Delete character
- **Ctrl+C**: Clear conversation
- **Ctrl+L**: Clear screen (reset scroll to top)

**Navigation:**
- **Up/Down**: Scroll one line at a time
- **Page Up/Page Down**: Scroll by page
- **Home**: Jump to top of conversation
- **End**: Jump to bottom of conversation

**Application:**
- **Ctrl+Q**: Quit

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
    ├── chat_view.zig     # Chat display with syntax highlighting
    ├── input_view.zig    # Input field
    ├── modal_view.zig    # Provider/model selection modal
    └── syntax.zig        # Syntax highlighting (Zig, Python, JS, JSON)
```

## Development Status

- [x] Phase 1: Foundation with TUI (OpenAI, Build mode)
- [x] Phase 2: Multi-Provider Support with Streaming
  - [x] OpenAI with streaming
  - [x] Anthropic Claude with streaming
  - [x] Z.AI with streaming
  - [x] DeepSeek via OpenRouter
  - [x] Qwen via OpenRouter
  - [x] Generic OpenRouter support
- [x] Phase 3: Dual-Mode System (Plan/Build mode switching)
- [x] Phase 4: Model Selection Modal
- [x] Phase 5: Enhanced Features
  - [x] Syntax highlighting (Zig, Python, JavaScript, JSON)
  - [x] Code block detection and rendering
  - [x] Advanced scrolling (arrows, Page Up/Down, Home/End)
  - [x] Error display with color coding
  - [x] Ctrl+L clear screen
- [x] Phase 6: Testing & Documentation
  - [x] Parser unit tests (8 test cases)
  - [x] Tools unit tests (7 test cases)
  - [x] Streaming unit tests (13 test cases)
  - [x] Syntax unit tests (15 test cases)
  - [x] Integration testing guide (TESTING.md)
  - [x] Example configuration (.env.example)
  - [x] Comprehensive documentation

## Testing

### Run All Tests

```bash
zig build test
```

This runs comprehensive unit test suites:
- **Parser Tests**: Tool invocation extraction, JSON parsing, malformed input handling
- **Tools Tests**: File operations (read_file, list_files, edit_file)
- **Streaming Tests**: SSE parser, OpenAI/Anthropic formats, buffering, error handling
- **Syntax Tests**: Tokenization, keyword detection, code block parsing for Zig/Python/JS/JSON

### Manual Testing

See [TESTING.md](TESTING.md) for comprehensive integration testing procedures including:
- Provider/model switching
- Dual-mode system (Plan/Build)
- Tool execution and chaining
- Syntax highlighting verification
- Scrolling and navigation
- Error handling
- Multi-provider testing

### Test Coverage

All core functionality is covered by automated tests:
- ✅ 40+ unit tests across 4 test suites
- ✅ Parser: 8 test cases
- ✅ Tools: 7 test cases
- ✅ Streaming: 13 test cases
- ✅ Syntax: 15 test cases

## License

See LICENSE file.

## Contributing

Contributions are welcome! To contribute:

1. **Fork the repository**
2. **Create a feature branch:** `git checkout -b feature/my-feature`
3. **Make your changes** and ensure tests pass: `zig build test`
4. **Follow the code style:** Match existing Zig conventions
5. **Add tests** for new functionality
6. **Update documentation** if needed
7. **Submit a pull request**

### Development Guidelines

- Write clear commit messages
- Keep changes focused and atomic
- Ensure all tests pass before submitting PR
- Add unit tests for new features
- Update README.md and TESTING.md for user-facing changes
- Follow Zig best practices for memory management

### Testing Your Changes

```bash
# Run all tests
zig build test

# Build and run the application
zig build run

# Manual testing
# See TESTING.md for comprehensive checklist
```
