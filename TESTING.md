# Testing Guide for zcode

This document provides comprehensive testing procedures for zcode, including unit tests, integration tests, and manual testing checklists.

## Unit Tests

### Running All Tests

```bash
zig build test
```

This runs all unit test suites:
- Parser tests (tool invocation extraction)
- Tools tests (read_file, list_files, edit_file)
- Streaming tests (SSE parser)
- Syntax tests (syntax highlighting and code block detection)

### Running Specific Test Suites

```bash
# Parser tests only
zig test test/parser_test.zig

# Tools tests only
zig test test/tools_test.zig

# Streaming tests only
zig test test/streaming_test.zig

# Syntax tests only
zig test test/syntax_test.zig
```

### Test Coverage

**Parser Tests:**
- ✅ Extract single tool invocation
- ✅ Extract multiple tool invocations
- ✅ Handle no tool invocations
- ✅ Parse nested JSON objects
- ✅ Handle malformed JSON gracefully
- ✅ Parse multiline JSON
- ✅ Handle underscores in tool names
- ✅ Handle empty JSON objects

**Tools Tests:**
- ✅ read_file: Returns file content
- ✅ read_file: Handles non-existent files
- ✅ list_files: Returns directory listing
- ✅ list_files: Lists files and subdirectories
- ✅ edit_file: Replaces text in existing files
- ✅ edit_file: Creates new files (empty old_str)
- ✅ edit_file: Handles old_str not found

**Streaming Tests:**
- ✅ Parse complete SSE events
- ✅ Parse multiple events in sequence
- ✅ Detect [DONE] marker
- ✅ Buffer incomplete events
- ✅ Handle Anthropic format (content_block_delta)
- ✅ Handle OpenAI format (choices/delta/content)
- ✅ Handle empty content deltas
- ✅ Handle mixed partial chunks
- ✅ Ignore event: lines
- ✅ Handle malformed JSON gracefully

**Syntax Tests:**
- ✅ Detect Zig keywords (const, fn, struct, etc.)
- ✅ Detect Python keywords (def, return, class, etc.)
- ✅ Detect JavaScript keywords (const, async, await, etc.)
- ✅ Detect string literals
- ✅ Detect numbers
- ✅ Detect comments (Zig //, Python #)
- ✅ Detect code blocks in markdown
- ✅ Handle code blocks without language
- ✅ Language detection from fence tags
- ✅ JSON tokenization
- ✅ Type name detection (uppercase identifiers)

---

## Integration Tests

### Prerequisites

Set up at least one API key for testing:

```bash
export OPENAI_API_KEY="sk-..."
# OR
export ANTHROPIC_API_KEY="sk-ant-..."
# OR
export ZAI_API_KEY="..."
# etc.
```

### Manual Testing Checklist

#### 1. Basic Functionality

**Start Application:**
```bash
zig build run
```

- [ ] Application starts without errors
- [ ] Status bar displays correct mode `[BUILD]` or `[PLAN]`
- [ ] Status bar shows provider and model (e.g., `OpenAI | gpt-4o`)
- [ ] Input prompt appears: `> `
- [ ] Key hints visible at bottom

**Simple Conversation:**
- [ ] Type a message and press Enter
- [ ] Message appears in conversation as "You: ..."
- [ ] Streaming indicator `[Streaming]` appears in status bar
- [ ] Assistant response streams in real-time
- [ ] Response appears as "Assistant: ..."
- [ ] Streaming indicator disappears when complete

**Clear Conversation:**
- [ ] Press Ctrl+C to clear conversation
- [ ] Conversation history clears
- [ ] System prompt is preserved
- [ ] Can start new conversation immediately

---

#### 2. Dual-Mode System

**Plan Mode:**
- [ ] Start application (should be in default mode)
- [ ] Press Tab to switch to Plan mode
- [ ] Status bar shows `[PLAN]`
- [ ] Ask agent to read a file: "Can you read src/main.zig?"
- [ ] Agent successfully uses `read_file` tool
- [ ] Ask agent to edit a file: "Can you create a new file called test.txt?"
- [ ] Agent attempts to use `edit_file`
- [ ] Error message appears: "[Error] edit_file is not available in PLAN mode"
- [ ] Agent does not modify any files

**Build Mode:**
- [ ] Press Tab to switch to Build mode
- [ ] Status bar shows `[BUILD]`
- [ ] Ask agent to create a file: "Create a file called hello.txt with 'Hello World'"
- [ ] Agent successfully uses `edit_file` tool
- [ ] Verify file was created: `cat hello.txt`
- [ ] Content matches request
- [ ] Clean up: `rm hello.txt`

**Mode Persistence:**
- [ ] Switch between modes multiple times with Tab
- [ ] Conversation history is preserved across switches
- [ ] System prompt updates (only edit_file availability changes)

---

#### 3. Provider/Model Selection

**Open Modal:**
- [ ] Press Ctrl+P
- [ ] Modal window appears centered on screen
- [ ] Title: "Select Provider & Model"
- [ ] Current provider is shown and expanded
- [ ] Models listed under provider with `•` bullets
- [ ] Default model marked with `(default)`
- [ ] Current selection highlighted with `>`

**Navigate Modal:**
- [ ] Press Down arrow - cursor moves to next item
- [ ] Press Up arrow - cursor moves to previous item
- [ ] Navigate to a different provider header
- [ ] Press Enter on provider - provider expands/collapses
- [ ] Navigate to a model under a different provider
- [ ] Only providers with configured API keys are shown

**Select Model:**
- [ ] Navigate to a different model (e.g., OpenAI gpt-4o-mini)
- [ ] Press Enter
- [ ] Modal closes
- [ ] Status bar updates to show new provider and model
- [ ] Send a test message
- [ ] Response comes from new provider/model
- [ ] Conversation history is preserved

**Cancel Selection:**
- [ ] Press Ctrl+P to open modal
- [ ] Press Esc
- [ ] Modal closes without changes
- [ ] Provider and model remain unchanged

---

#### 4. Tool Execution

**read_file:**
- [ ] Ask: "Can you read the README.md file?"
- [ ] Agent invokes `read_file({"filename": "README.md"})`
- [ ] Tool result appears with file content
- [ ] Agent summarizes or discusses the content

**list_files:**
- [ ] Ask: "What files are in the src directory?"
- [ ] Agent invokes `list_files({"path": "src"})`
- [ ] Tool result shows list of files and directories
- [ ] Agent lists the files

**edit_file (create):**
- [ ] Ask: "Create a file called test.md with '# Test Document'"
- [ ] Agent invokes `edit_file` with empty old_str
- [ ] Tool result shows `"action": "created_file"`
- [ ] Verify: `cat test.md`
- [ ] File exists with correct content
- [ ] Clean up: `rm test.md`

**edit_file (modify):**
- [ ] Create test file: `echo "Hello World" > test.txt`
- [ ] Ask: "Change 'World' to 'Zig' in test.txt"
- [ ] Agent invokes `edit_file` with old_str="World", new_str="Zig"
- [ ] Tool result shows `"action": "edited"`
- [ ] Verify: `cat test.txt`
- [ ] Content is "Hello Zig"
- [ ] Clean up: `rm test.txt`

**Tool Chain:**
- [ ] Ask: "List files in src/, then read src/main.zig"
- [ ] Agent executes list_files first
- [ ] Then executes read_file
- [ ] Agent loop continues until all tools complete
- [ ] Agent provides comprehensive response

---

#### 5. Syntax Highlighting

**Zig Code:**
- [ ] Ask: "Show me a Zig struct example"
- [ ] Agent responds with code fence: \`\`\`zig
- [ ] Keywords (const, fn, struct) appear in blue
- [ ] Strings appear in green
- [ ] Numbers appear in cyan
- [ ] Comments appear in gray
- [ ] Code is indented 2 spaces

**Python Code:**
- [ ] Ask: "Show me a Python function"
- [ ] Code fence: \`\`\`python
- [ ] Keywords (def, return) in blue
- [ ] Strings in green
- [ ] Comments (#) in gray

**JavaScript Code:**
- [ ] Ask: "Show me an async JavaScript function"
- [ ] Code fence: \`\`\`javascript
- [ ] Keywords (const, async, await) in blue
- [ ] Template literals in green

**JSON Code:**
- [ ] Ask: "Show me a JSON example"
- [ ] Code fence: \`\`\`json
- [ ] Strings in green
- [ ] Numbers in cyan
- [ ] Keywords (true, false, null) in blue

**Multiple Code Blocks:**
- [ ] Ask for multiple code examples in one response
- [ ] All code blocks highlighted correctly
- [ ] Different languages can coexist in one message

---

#### 6. Navigation & Scrolling

**Line Scrolling:**
- [ ] Have a long conversation (10+ messages)
- [ ] Press Up arrow - scroll up one message
- [ ] Press Down arrow - scroll down one message
- [ ] Scroll to top of conversation
- [ ] Scroll back to bottom

**Page Scrolling:**
- [ ] Press Page Up - jump up by ~10 messages
- [ ] Press Page Down - jump down by ~10 messages
- [ ] Verify smooth navigation

**Jump Navigation:**
- [ ] Press Home - jump to conversation start
- [ ] Verify first message visible
- [ ] Press End - jump to conversation end
- [ ] Verify latest message visible

**Clear Screen:**
- [ ] Scroll somewhere in the middle
- [ ] Press Ctrl+L
- [ ] Scroll resets to top
- [ ] Conversation history preserved

**Auto-Scroll:**
- [ ] Scroll to middle of conversation
- [ ] Type new message and press Enter
- [ ] Verify scroll automatically jumps to bottom
- [ ] New response immediately visible

---

#### 7. Error Handling

**Network Error:**
- [ ] Disable network or use invalid API key
- [ ] Send a message
- [ ] Error message appears in bold red
- [ ] Application doesn't crash
- [ ] Can continue after fixing network/key

**Invalid Tool Call:**
- [ ] (Advanced) If possible, manually trigger an invalid tool call
- [ ] Error message shows in conversation
- [ ] Agent loop continues
- [ ] Application remains stable

**File Not Found:**
- [ ] Ask: "Read the file nonexistent.txt"
- [ ] Agent calls read_file with non-existent file
- [ ] Tool returns error
- [ ] Error shows in conversation
- [ ] Agent acknowledges file doesn't exist

**Permission Denied:**
- [ ] Create file without read permissions: `touch noperm.txt && chmod 000 noperm.txt`
- [ ] Ask: "Read noperm.txt"
- [ ] Tool returns permission error
- [ ] Error handled gracefully
- [ ] Clean up: `chmod 644 noperm.txt && rm noperm.txt`

---

#### 8. Keyboard Shortcuts

Test all documented shortcuts:

**Mode & Configuration:**
- [ ] Tab - switches modes
- [ ] Ctrl+P - opens modal

**Conversation:**
- [ ] Enter - submits message
- [ ] Backspace - deletes character
- [ ] Ctrl+C - clears conversation
- [ ] Ctrl+L - clears screen/resets scroll

**Navigation:**
- [ ] Up/Down - scroll line by line
- [ ] Page Up/Page Down - page scrolling
- [ ] Home - jump to top
- [ ] End - jump to bottom

**Application:**
- [ ] Ctrl+Q - quits application cleanly

---

#### 9. Multi-Provider Testing

Test with each configured provider:

**OpenAI:**
- [ ] Set `OPENAI_API_KEY`
- [ ] Select OpenAI provider with Ctrl+P
- [ ] Select model (gpt-4o, gpt-4o-mini, o1, etc.)
- [ ] Send test message
- [ ] Streaming works correctly
- [ ] Tool calls work
- [ ] Response quality is good

**Anthropic:**
- [ ] Set `ANTHROPIC_API_KEY`
- [ ] Select Anthropic provider
- [ ] Select model (claude-sonnet-4-5, claude-opus-4-5, etc.)
- [ ] Send test message
- [ ] Streaming works correctly
- [ ] Tool calls work

**Z.AI:**
- [ ] Set `ZAI_API_KEY`
- [ ] Select Z.AI provider
- [ ] Model: glm-4.7
- [ ] Test message and tools

**DeepSeek (via OpenRouter):**
- [ ] Set `DEEPSEEK_API_KEY` or `OPENROUTER_API_KEY`
- [ ] Select DeepSeek provider
- [ ] Model: deepseek-chat
- [ ] Test message and tools

**Qwen (via OpenRouter):**
- [ ] Set `QWEN_API_KEY` or `OPENROUTER_API_KEY`
- [ ] Select Qwen provider
- [ ] Model: qwen-max
- [ ] Test message and tools

**OpenRouter (Generic):**
- [ ] Set `OPENROUTER_API_KEY`
- [ ] Select OpenRouter provider
- [ ] Test with various models
- [ ] Verify streaming and tools

---

## Performance Testing

**Streaming Performance:**
- [ ] Long response streams smoothly without lag
- [ ] UI remains responsive during streaming
- [ ] No memory leaks during extended sessions

**Large Conversations:**
- [ ] Have 50+ message conversation
- [ ] Scrolling remains smooth
- [ ] No performance degradation
- [ ] Memory usage remains reasonable

**Large Files:**
- [ ] Read a large file (>10KB)
- [ ] Tool executes without timeout
- [ ] Content displayed correctly
- [ ] Syntax highlighting works on large code blocks

---

## Edge Cases

**Special Characters:**
- [ ] Send message with emojis
- [ ] Send message with unicode characters
- [ ] Tool calls with paths containing spaces
- [ ] All handled correctly

**Long File Paths:**
- [ ] Create deeply nested directories
- [ ] Use tools with long paths
- [ ] Paths handled correctly

**Binary Files:**
- [ ] Try to read a binary file (e.g., image)
- [ ] Error handled gracefully
- [ ] Application doesn't crash

**Concurrent Operations:**
- [ ] Send message during streaming
- [ ] Switch modes during streaming
- [ ] Application handles gracefully

---

## Regression Testing

Before each release, run:

1. **All Unit Tests:** `zig build test`
2. **Basic Functionality:** Sections 1-2
3. **Provider Testing:** Section 9 with at least 2 providers
4. **Tool Testing:** Section 4 (all tools)
5. **UI Features:** Sections 3, 5, 6

---

## Bug Reporting

When reporting bugs, include:

1. **Environment:**
   - OS and version
   - Zig version
   - Provider being used
   - Model being used

2. **Steps to Reproduce:**
   - Exact sequence of actions
   - Input provided
   - Expected vs actual behavior

3. **Logs/Errors:**
   - Error messages (screenshots or text)
   - Console output if applicable

4. **Configuration:**
   - Environment variables set
   - Any custom settings

---

## Test Automation

Future improvements:
- [ ] CI/CD pipeline for automated testing
- [ ] Integration test scripts
- [ ] Performance benchmarks
- [ ] Code coverage reports
