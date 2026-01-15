# Product Requirements Document: zcode

## Executive Summary

**Product Name**: zcode
**Version**: 1.0
**Date**: 2026-01-15
**Status**: Planning

zcode - современный coding agent на языке Zig с rich TUI интерфейсом, поддерживающий множество LLM провайдеров. Это улучшенная версия простого Python REPL агента с добавлением профессионального терминального интерфейса, streaming responses и dual-mode работы (plan/build).

---

## 1. Product Vision

### 1.1 Problem Statement

Существующие coding agents имеют ограничения:
- Привязка к одному LLM провайдеру
- Простой текстовый интерфейс без rich UI
- Отсутствие разделения между планированием и реализацией
- Нет streaming responses для больших ответов
- Отсутствие syntax highlighting в коде

### 1.2 Solution

zcode предоставляет:
- **Multi-provider support**: 6 LLM провайдеров (OpenAI, Claude, z.ai, DeepSeek, Qwen, OpenRouter)
- **Dual-mode interface**: Plan режим (обдумывание) и Build режим (реализация)
- **Rich TUI**: Современный интерфейс с libvaxis
- **Streaming responses**: Real-time отображение ответов
- **Syntax highlighting**: Подсветка кода во всех сообщениях
- **Flexible model selection**: Выбор провайдера и модели через модальное окно

### 1.3 Target Audience

- Software developers
- DevOps engineers
- Technical writers
- Students learning programming
- Anyone working with code files

---

## 2. Core Features

### 2.1 Dual-Mode System

#### Plan Mode
**Purpose**: Обдумывание и проектирование решений

**Characteristics**:
- LLM анализирует задачу
- Создаёт план действий
- Может использовать read-only tools (read_file, list_files)
- **Не выполняет** edit_file в этом режиме
- Визуальный индикатор: `[PLAN]` в статус баре

**Use Cases**:
- "Как мне лучше организовать этот код?"
- "Какой алгоритм использовать для этой задачи?"
- "Проанализируй существующую кодовую базу"

#### Build Mode
**Purpose**: Реализация и выполнение изменений

**Characteristics**:
- LLM выполняет действия
- Может использовать все tools включая edit_file
- Создаёт и модифицирует файлы
- Визуальный индикатор: `[BUILD]` в статус баре

**Use Cases**:
- "Создай новый модуль для парсинга JSON"
- "Исправь этот баг в коде"
- "Реализуй функцию сортировки"

#### Mode Switching
**Trigger**: Tab key
**Behavior**:
- Переключает между Plan ↔ Build
- Сохраняет conversation history
- Обновляет доступные tools в system prompt
- Визуальная индикация текущего режима

---

### 2.2 Multi-Provider LLM Support

#### Supported Providers

| Provider | Default Model | Endpoint |
|----------|--------------|----------|
| OpenAI | gpt-4o | api.openai.com |
| Anthropic | claude-sonnet-4-5 | api.anthropic.com |
| Z.AI | glm-4.7 | api.z.ai |
| DeepSeek | deepseek-chat | openrouter.ai |
| Qwen | qwen-max | openrouter.ai |
| OpenRouter | gpt-4o | openrouter.ai |

#### Provider Selection UI

**Trigger**: Ctrl+P

**Modal Window Design**:
```
┌──────────────────────────────────────┐
│      Select Provider & Model         │
├──────────────────────────────────────┤
│                                      │
│  > OpenAI                            │ <- Selected provider
│    • gpt-4o (default)                │
│    • gpt-4o-mini                     │
│    • o1                              │
│    • o1-mini                         │
│                                      │
│  Anthropic                           │
│    • claude-sonnet-4-5 (default)     │
│    • claude-opus-4-5                 │
│    • claude-haiku-4                  │
│                                      │
│  Z.AI                                │
│    • glm-4.7 (default)               │
│                                      │
│  DeepSeek                            │
│    • deepseek-chat (default)         │
│    • deepseek-coder                  │
│                                      │
│  Qwen                                │
│    • qwen-max (default)              │
│    • qwen-plus                       │
│                                      │
│  OpenRouter                          │
│    • (custom model input)            │
│                                      │
├──────────────────────────────────────┤
│ ↑↓: Navigate | Enter: Select         │
│ Esc: Cancel                          │
└──────────────────────────────────────┘
```

**Behavior**:
- Arrow keys navigate providers and models
- Enter confirms selection
- Esc closes without changes
- Shows current selection with `>`
- Default model marked with `(default)`
- Closes modal after selection
- Updates status bar immediately

#### Model Switching
- Instant switching without restarting app
- Conversation history preserved
- System prompt regenerated for new provider
- Streaming capabilities adjusted per provider

---

### 2.3 Rich TUI Interface

#### Layout

```
┌───────────────────────────────────────────────────────────────┐
│ [PLAN] zcode                     OpenAI | gpt-4o [Streaming] │ <- Status Bar
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  You: Can you analyze the structure of this project?         │
│                                                               │
│  Assistant: I'll read the directory structure.               │
│  tool: list_files({"path": "."})                             │
│                                                               │
│  [Tool Result]                                               │
│  {                                                           │
│    "path": "/Users/pavlenko/code/zcode",                    │
│    "files": [                                               │ <- Chat View
│      {"filename": "src", "type": "dir"},                    │    (scrollable)
│      {"filename": "build.zig", "type": "file"}              │
│    ]                                                         │
│  }                                                           │
│                                                               │
│  Assistant: The project has a src directory and...          │
│  ▼ [Streaming response continues...]                        │
│                                                               │
│                                                               │
├───────────────────────────────────────────────────────────────┤
│ > Your message here_                                         │ <- Input Field
├───────────────────────────────────────────────────────────────┤
│ Tab: Switch Mode | Ctrl+P: Select Model | Ctrl+Q: Quit     │ <- Shortcuts
└───────────────────────────────────────────────────────────────┘
```

#### Status Bar Components

**Left Section**:
- Mode indicator: `[PLAN]` or `[BUILD]`
- App name: `zcode`

**Right Section**:
- Provider: `OpenAI`
- Separator: `|`
- Model: `gpt-4o`
- Streaming indicator: `[Streaming]` (only when active)

**Colors**:
- Background: Blue (#3b82f6)
- Text: White
- Mode indicator: Bold
- Streaming indicator: Blinking/animated

#### Chat View

**Features**:
- Role-based message colors:
  - User: Blue (#3b82f6)
  - Assistant: Yellow (#eab308)
  - Tool Result: Magenta (#a855f7)
  - System: Green (#22c55e)
- Syntax highlighting for code blocks
- Automatic word wrapping
- Smooth scrolling
- Streaming text animation
- Code fence detection (```language ... ```)

**Scrolling**:
- Up/Down arrows: Scroll by line
- Page Up/Down: Scroll by page
- Home/End: Jump to top/bottom
- Auto-scroll to bottom on new message

#### Input Field

**Features**:
- Multi-line editing
- Cursor position indicator
- Character echo
- Line wrapping for long input

**Controls**:
- Enter: Submit message (single line)
- Shift+Enter: New line (multi-line)
- Backspace: Delete character
- Ctrl+U: Clear input
- Ctrl+W: Delete word

#### Model Selection Modal

**Appearance**:
- Centered overlay
- Semi-transparent background (dim main view)
- Border with rounded corners
- Shadow effect

**Navigation**:
- Up/Down: Move cursor
- Left/Right: Collapse/expand provider sections
- Enter: Select model
- Esc: Cancel
- /: Start typing to filter

**Behavior**:
- Remember last position
- Show checkmark for current selection
- Highlight default models
- Show model descriptions (hover/select)

---

### 2.4 Tool System

#### Core Tools

**1. read_file**
```
Name: read_file
Description: Gets the full content of a file
Parameters:
  - filename (string): Path to file (absolute or relative)
Returns:
  {
    "file_path": "/absolute/path/to/file",
    "content": "file contents..."
  }
Available in: Plan ✓, Build ✓
```

**2. list_files**
```
Name: list_files
Description: Lists files in a directory
Parameters:
  - path (string): Directory path (default: current directory)
Returns:
  {
    "path": "/absolute/path/to/dir",
    "files": [
      {"filename": "example.txt", "type": "file"},
      {"filename": "src", "type": "dir"}
    ]
  }
Available in: Plan ✓, Build ✓
```

**3. edit_file**
```
Name: edit_file
Description: Replaces text in file or creates new file
Parameters:
  - path (string): File path
  - old_str (string): Text to replace (empty = create file)
  - new_str (string): Replacement text
Returns:
  {
    "path": "/absolute/path/to/file",
    "action": "created_file" | "edited" | "old_str not found"
  }
Available in: Plan ✗, Build ✓
```

#### Tool Execution Flow

1. **LLM Response** → Contains `tool: TOOL_NAME({JSON_ARGS})`
2. **Parser** → Extracts tool invocations
3. **Registry** → Looks up tool by name
4. **Validation** → Checks mode restrictions (edit_file only in Build)
5. **Execution** → Calls tool function with arguments
6. **Result** → Adds `tool_result({...})` to conversation
7. **Continue** → Sends updated conversation to LLM

#### Mode Restrictions

| Tool | Plan Mode | Build Mode |
|------|-----------|------------|
| read_file | ✓ Allowed | ✓ Allowed |
| list_files | ✓ Allowed | ✓ Allowed |
| edit_file | ✗ **Blocked** | ✓ Allowed |

**Plan Mode Blocking**:
- If LLM tries to use edit_file in Plan mode:
  - Show error in chat: `[Error] edit_file is not available in PLAN mode. Switch to BUILD mode with Tab.`
  - Do not execute the tool
  - Continue conversation with error message

---

### 2.5 Streaming Responses

#### Implementation

**Server-Sent Events (SSE)**:
- All providers use SSE format
- Parse `data: {...}\n\n` chunks
- Extract content deltas
- Detect `[DONE]` marker

**Display Behavior**:
- Start showing text immediately
- Append each chunk to message
- Auto-scroll to follow streaming
- Show streaming indicator in status bar
- Cursor/animation at end of streaming text

**Performance**:
- Buffer chunks for smooth display (50ms intervals)
- Avoid re-rendering entire conversation
- Update only current message region
- Efficient text append

---

### 2.6 Syntax Highlighting

#### Supported Languages

- **Zig**: Keywords, types, functions, strings, numbers, comments
- **Python**: Keywords, decorators, strings, f-strings, numbers, comments
- **JavaScript/TypeScript**: Keywords, types, strings, template literals, numbers, comments
- **JSON**: Structure (braces, brackets), keys, values
- **Generic**: Fallback with basic keyword detection

#### Color Scheme

| Token Type | Color | Use Case |
|------------|-------|----------|
| Keyword | Blue (#3b82f6) | const, var, fn, if, for |
| String | Green (#22c55e) | "text", 'text' |
| Number | Cyan (#06b6d4) | 42, 3.14 |
| Comment | Gray (#6b7280) | // comment, /* */ |
| Operator | Magenta (#a855f7) | +, -, *, = |
| Function | Yellow (#eab308) | functionName() |
| Type | Purple (#8b5cf6) | i32, String |

#### Detection

**Code Block Markers**:
```
```zig
// Zig code here
```
```python
# Python code here
```
```

**Inline Code**: \`code\` (no highlighting, just styling)

**Auto-Detection**: If language not specified, attempt to detect from content

---

### 2.7 Configuration System

#### Configuration File

**Location** (in order of precedence):
1. `./config.zon` (project-specific)
2. `~/.config/zcode/config.zon` (user-wide)
3. Environment variables
4. Built-in defaults

**Format** (`config.zon`):
```zig
.{
    .api_keys = .{
        .openai = "sk-...",
        .anthropic = "sk-ant-...",
        .zai = "...",
        .openrouter = "sk-or-...",
    },
    .default_provider = .anthropic,
    .default_mode = .plan, // or .build
    .models = .{
        .openai = .{
            .default = "gpt-4o",
            .available = .{ "gpt-4o", "gpt-4o-mini", "o1", "o1-mini" },
        },
        .anthropic = .{
            .default = "claude-sonnet-4-5-20250929",
            .available = .{
                "claude-sonnet-4-5-20250929",
                "claude-opus-4-5-20251101",
                "claude-haiku-4-20250415"
            },
        },
        .zai = .{
            .default = "glm-4.7",
            .available = .{ "glm-4.7" },
        },
        .deepseek = .{
            .default = "deepseek-chat",
            .available = .{ "deepseek-chat", "deepseek-coder" },
        },
        .qwen = .{
            .default = "qwen-max",
            .available = .{ "qwen-max", "qwen-plus" },
        },
        .openrouter = .{
            .default = "openai/gpt-4o",
            .available = .{}, // User can type any model
        },
    },
    .max_tokens = 2000,
    .theme = .{
        .user_color = .blue,
        .assistant_color = .yellow,
        .tool_color = .magenta,
        .system_color = .green,
    },
}
```

#### Environment Variables

**API Keys**:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `ZAI_API_KEY`
- `DEEPSEEK_API_KEY`
- `QWEN_API_KEY`
- `OPENROUTER_API_KEY`

**Overrides**:
- `ZCODE_DEFAULT_PROVIDER` (openai|anthropic|zai|deepseek|qwen|openrouter)
- `ZCODE_DEFAULT_MODE` (plan|build)
- `ZCODE_MAX_TOKENS` (integer)

---

## 3. User Experience

### 3.1 User Workflows

#### Workflow 1: Quick Code Analysis (Plan Mode)

1. User starts zcode
2. Default mode: `[PLAN]`
3. User asks: "What does this function do?"
4. LLM uses `read_file` to fetch code
5. LLM explains function
6. No file modifications made

#### Workflow 2: Implement Feature (Build Mode)

1. User in `[PLAN]` mode
2. Asks: "Plan how to add logging"
3. LLM analyzes codebase with `read_file`, `list_files`
4. LLM provides implementation plan
5. User switches to `[BUILD]` with Tab
6. User says: "Implement the plan"
7. LLM uses `edit_file` to make changes
8. User reviews changes

#### Workflow 3: Switch LLM Provider

1. User presses Ctrl+P
2. Modal window appears
3. User navigates to "Anthropic"
4. Selects "claude-opus-4-5"
5. Modal closes
6. Status bar updates: `Anthropic | claude-opus-4-5`
7. Next message uses new provider

#### Workflow 4: Streaming Long Response

1. User asks complex question
2. LLM starts responding
3. Status bar shows `[Streaming]`
4. Text appears word-by-word
5. Chat auto-scrolls to follow
6. Streaming completes
7. `[Streaming]` indicator disappears

### 3.2 Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| Tab | Switch Plan ↔ Build | Global |
| Ctrl+P | Open provider/model selector | Global |
| Ctrl+Q | Quit application | Global |
| Ctrl+C | Clear conversation | Global |
| Ctrl+L | Clear screen | Global |
| Ctrl+U | Clear input field | Input focused |
| Ctrl+W | Delete word in input | Input focused |
| Enter | Submit message | Input focused |
| Shift+Enter | New line in input | Input focused |
| ↑ / ↓ | Scroll chat | Chat view |
| Page Up/Down | Scroll chat by page | Chat view |
| Home / End | Jump to top/bottom | Chat view |
| Esc | Close modal | Modal open |

### 3.3 Error Handling

#### Network Errors

**Scenario**: API request fails (timeout, connection refused)

**Display**:
```
[Error] Failed to connect to OpenAI API
Reason: Connection timeout after 30s
Suggestion: Check your internet connection or API status
```

**Behavior**:
- Show in chat with red color
- Keep conversation history
- Allow retry
- Don't crash application

#### Invalid API Key

**Scenario**: API returns 401 Unauthorized

**Display**:
```
[Error] Invalid API key for OpenAI
Suggestion: Check OPENAI_API_KEY in config or environment
```

**Behavior**:
- Show in chat
- Prevent further requests to same provider
- Suggest switching provider with Ctrl+P

#### Tool Errors

**Scenario**: File not found in `read_file`

**Display**:
```
tool_result({
  "error": "File not found: /path/to/missing.txt",
  "suggestion": "Check the file path and try again"
})
```

**Behavior**:
- Return error in tool result
- LLM can respond to error
- Don't crash

#### Mode Restriction Error

**Scenario**: LLM tries `edit_file` in Plan mode

**Display**:
```
[Error] edit_file is not available in PLAN mode
Suggestion: Switch to BUILD mode with Tab to make file changes
```

**Behavior**:
- Block tool execution
- Show error message
- Continue conversation

---

## 4. Technical Requirements

### 4.1 Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| App startup time | < 500ms | Time to first render |
| Input latency | < 50ms | Keystroke to display |
| Streaming latency | < 100ms | Chunk receive to display |
| Scroll performance | 60 FPS | Frame rate during scroll |
| Memory usage | < 100MB | Steady state |
| API response time | Provider-dependent | Log and display |

### 4.2 Compatibility

**Operating Systems**:
- macOS 12+ ✓
- Linux (Ubuntu 20.04+) ✓
- Windows 10+ ✓ (with proper terminal)

**Terminals**:
- iTerm2 ✓
- Terminal.app ✓
- Alacritty ✓
- Kitty ✓
- Windows Terminal ✓
- tmux ✓
- Screen ✓

**Zig Version**: 0.13.0 or later

### 4.3 Security

**API Key Storage**:
- Never commit keys to version control
- Use environment variables or config file
- Config file permissions: 600 (user read/write only)
- Warn if config.zon is world-readable

**File Access**:
- Resolve all paths to absolute
- Prevent directory traversal attacks
- Warn on sensitive file access (.env, credentials.json)
- Respect filesystem permissions

**Network Security**:
- HTTPS only for all API calls
- Validate SSL certificates
- No insecure fallbacks

### 4.4 Reliability

**Error Recovery**:
- Graceful degradation on component failure
- No data loss on crash
- Save conversation history
- Resume from last state

**Robustness**:
- Handle malformed JSON from LLM
- Handle incomplete SSE streams
- Handle terminal resize
- Handle out-of-memory conditions

---

## 5. Future Enhancements

### 5.1 Phase 2 Features (v2.0)

**Additional Tools**:
- `write_file`: Create new file with content
- `search_files`: Grep across codebase
- `run_command`: Execute shell commands safely
- `git_diff`: Show git changes
- `git_commit`: Create commits

**Advanced UI**:
- Split-pane view (chat + file preview)
- File tree browser sidebar
- Minimap for long files
- Search within conversation (Ctrl+F)

**Conversation Management**:
- Save/load conversations
- Export to markdown
- Conversation branching
- Conversation templates

**Configuration UI**:
- In-app settings editor (Ctrl+,)
- Visual theme picker
- Keyboard shortcut customization

### 5.2 Phase 3 Features (v3.0)

**Context Management**:
- Automatic context window management
- Summarize old messages
- Prioritize relevant context
- Token usage display and limits

**Integration**:
- LSP integration (code intelligence)
- Git deep integration
- Project templates
- Plugin system for custom tools

**Collaboration**:
- Share conversations
- Team workspaces
- Collaborative editing

**Advanced LLM Features**:
- Temperature/top_p controls
- Multiple models in parallel
- Model comparison mode
- Response caching

---

## 6. Success Metrics

### 6.1 Launch Criteria (v1.0)

**Functional**:
- ✅ All 6 providers working
- ✅ Plan/Build mode switching
- ✅ Model selection modal
- ✅ All 3 tools implemented
- ✅ Streaming responses
- ✅ Syntax highlighting
- ✅ All keyboard shortcuts

**Quality**:
- ✅ Zero crashes in 1 hour session
- ✅ No memory leaks
- ✅ All unit tests pass
- ✅ Documentation complete

**Performance**:
- ✅ < 500ms startup
- ✅ < 50ms input latency
- ✅ 60 FPS scrolling

### 6.2 User Satisfaction

**Target Metrics**:
- 90% task completion rate
- < 5% error rate
- Positive feedback on UI/UX
- Fast adoption by early users

---

## 7. Open Questions

1. **Conversation Persistence**: Should we auto-save conversations? Where?
2. **Token Limits**: How to handle hitting token limits mid-conversation?
3. **Multiple Tools**: Should LLM be able to call multiple tools in one response?
4. **Custom Tools**: Plugin system architecture for v2.0?
5. **Offline Mode**: Should we support local models (llama.cpp)?

---

## Appendix A: Comparison with Python Version

| Feature | Python Version | zcode (Zig) |
|---------|---------------|-------------|
| UI | Simple REPL | Rich TUI (libvaxis) |
| Providers | OpenAI only | 6 providers |
| Streaming | No | Yes |
| Syntax Highlighting | No | Yes |
| Modes | Single | Dual (Plan/Build) |
| Model Selection | Hardcoded | Dynamic modal |
| Tools | 3 (read, list, edit) | 3+ (extensible) |
| Performance | ~50MB RAM | ~30MB RAM |
| Startup Time | ~1s | ~0.3s |

---

## Appendix B: Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Language | Zig 0.13+ | Performance, safety, modern |
| TUI Library | libvaxis | Modern, feature-rich |
| HTTP Client | std.http.Client | Built-in, no deps |
| JSON Parser | std.json | Built-in, fast |
| Syntax Highlighting | Custom lexer | Minimal deps, control |
| Build System | Zig build system | Native, simple |
| Testing | Zig test | Built-in |

---

**Document Version**: 1.0
**Last Updated**: 2026-01-15
**Next Review**: After Phase 1 completion
