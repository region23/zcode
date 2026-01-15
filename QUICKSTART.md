# Quick Start Guide

Get up and running with zcode in 5 minutes.

## Prerequisites

- Zig 0.13.0 or later ([download](https://ziglang.org/download/))
- At least one LLM API key

## Installation

1. **Clone the repository** (or download the source):
   ```bash
   cd /path/to/zcode
   ```

2. **Fetch dependencies**:
   ```bash
   zig fetch --save git+https://github.com/rockorager/libvaxis
   ```

3. **Build the project**:
   ```bash
   zig build
   ```

## Configuration

1. **Copy the environment template**:
   ```bash
   cp .env.example .env
   ```

2. **Add your API key** (choose one or more):
   
   Edit `.env` and uncomment/fill in your provider:
   
   ```bash
   # For OpenAI
   export OPENAI_API_KEY="sk-your-key-here"
   
   # OR for Anthropic Claude
   export ANTHROPIC_API_KEY="sk-ant-your-key-here"
   
   # OR for Z.AI
   export ZAI_API_KEY="your-key-here"
   ```

3. **Load the environment**:
   ```bash
   source .env
   ```

## First Run

```bash
zig build run
```

You should see the zcode terminal interface:

```
┌──────────────────────────────────────────────────────┐
│ [BUILD] zcode                    OpenAI | gpt-4o    │
├──────────────────────────────────────────────────────┤
│                                                      │
│                                                      │
├──────────────────────────────────────────────────────┤
│ > _                                                  │
├──────────────────────────────────────────────────────┤
│ Tab: Mode | Ctrl+P: Model | Ctrl+L: Clear | ...    │
└──────────────────────────────────────────────────────┘
```

## Try It Out

### 1. Ask a Simple Question

Type:
```
What is Zig programming language?
```

Press **Enter**. Watch the streaming response appear in real-time.

### 2. Use Tools

Try:
```
Can you read the README.md file and summarize it?
```

The agent will:
1. Use the `read_file` tool to read README.md
2. Show you the tool execution
3. Provide a summary

### 3. Create a File

Try:
```
Create a file called hello.zig with a simple main function
```

The agent will:
1. Use the `edit_file` tool to create the file
2. Confirm creation
3. You can verify: `cat hello.zig`

### 4. Switch Providers

1. Press **Ctrl+P** to open the provider modal
2. Navigate with **↑/↓** arrows
3. Press **Enter** on a different provider
4. Status bar updates with new provider
5. Next message uses the new provider

### 5. Switch Modes

1. Press **Tab** to toggle between **[PLAN]** and **[BUILD]** modes
2. In **Plan mode**: Agent can only read files (analysis/planning)
3. In **Build mode**: Agent can create/modify files (implementation)

## Essential Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **Enter** | Send message |
| **Tab** | Switch Plan/Build mode |
| **Ctrl+P** | Select provider/model |
| **Ctrl+C** | Clear conversation |
| **Ctrl+L** | Clear screen/reset scroll |
| **Ctrl+Q** | Quit |
| **PgUp/PgDn** | Scroll by page |
| **Home/End** | Jump to top/bottom |

## Common Tasks

### Read a File
```
Can you read src/main.zig?
```

### List Directory
```
What files are in the src/ directory?
```

### Create a New File
```
Create a new file called utils.zig with a helper function for string manipulation
```

### Modify a File
```
In test.txt, change "hello" to "goodbye"
```

### Analyze Code
Switch to **Plan mode** (Tab), then:
```
What's the architecture of this codebase? Read the main files and explain.
```

### Get Code Examples
```
Show me an example of error handling in Zig
```

Code will be syntax-highlighted automatically.

## Troubleshooting

### "Configuration error: NoApiKeyConfigured"

- Make sure you've set at least one API key in `.env`
- Run `source .env` to load the environment
- Check that your API key is valid

### "Failed to get LLM response"

- Verify your API key is correct
- Check your internet connection
- Try a different provider (Ctrl+P)

### Application Crashes

- Run tests: `zig build test`
- Check Zig version: `zig version` (needs 0.13.0+)
- Report issues at: https://github.com/anthropics/zcode/issues

## Next Steps

- Read [README.md](README.md) for complete documentation
- See [TESTING.md](TESTING.md) for testing procedures
- Explore `.env.example` for all configuration options
- Try different models via Ctrl+P
- Experiment with Plan vs Build modes

## Getting Help

- Type `/help` in the application (coming soon)
- Read the [README.md](README.md)
- Check [TESTING.md](TESTING.md) for troubleshooting
- Open an issue on GitHub

Happy coding with zcode! 🚀
