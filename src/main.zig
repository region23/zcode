const std = @import("std");
const vaxis = @import("vaxis");
const config = @import("config.zig");
const App = @import("app.zig");
const layout = @import("ui/layout.zig");
const modal_view = @import("ui/modal_view.zig");
const parser = @import("parser.zig");
const tools = @import("tools/registry.zig");
const api_common = @import("api/common.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load configuration
    var cfg = try config.Config.load(allocator);
    defer cfg.deinit();

    // Validate configuration
    cfg.validate() catch |err| {
        std.debug.print("Configuration error: {}\n", .{err});
        std.debug.print("Please set at least one API key via environment variables:\n", .{});
        std.debug.print("  OPENAI_API_KEY\n", .{});
        std.debug.print("  ANTHROPIC_API_KEY\n", .{});
        std.debug.print("  etc.\n", .{});
        return err;
    };

    // Initialize application state
    var app_state = try App.AppState.init(allocator, cfg);
    defer app_state.deinit();

    // Initialize vaxis
    var tty_buffer: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    // Main event loop
    var running = true;
    while (running) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    // Ctrl+P: Open provider/model selection modal
                    if (key.matches('p', .{ .ctrl = true })) {
                        app_state.openModal();
                    } else if (app_state.show_modal) {
                        // Modal is open - handle modal navigation
                        try handleModalInput(&app_state, key, allocator);
                    } else {
                        // Normal input handling
                        if (key.matches('c', .{ .ctrl = true })) {
                            // Ctrl+C: Clear conversation
                            app_state.clearConversation();
                        } else if (key.matches('l', .{ .ctrl = true })) {
                            // Ctrl+L: Clear screen (reset scroll)
                            app_state.scroll_offset = 0;
                        } else if (key.matches('q', .{ .ctrl = true })) {
                            // Ctrl+Q: Quit
                            running = false;
                        } else if (key.matches(vaxis.Key.tab, .{})) {
                            // Tab: Toggle mode
                            try app_state.toggleMode();
                        } else if (key.matches(vaxis.Key.page_up, .{})) {
                            // Page Up: Scroll up by page
                            const page_size: usize = 10;
                            if (app_state.scroll_offset >= page_size) {
                                app_state.scroll_offset -= page_size;
                            } else {
                                app_state.scroll_offset = 0;
                            }
                        } else if (key.matches(vaxis.Key.page_down, .{})) {
                            // Page Down: Scroll down by page
                            const page_size: usize = 10;
                            const max_scroll = if (app_state.conversation.getMessages().len > page_size)
                                app_state.conversation.getMessages().len - page_size
                            else
                                0;
                            app_state.scroll_offset = @min(app_state.scroll_offset + page_size, max_scroll);
                        } else if (key.matches(vaxis.Key.up, .{})) {
                            // Up: Scroll up by one line
                            if (app_state.scroll_offset > 0) {
                                app_state.scroll_offset -= 1;
                            }
                        } else if (key.matches(vaxis.Key.down, .{})) {
                            // Down: Scroll down by one line
                            const messages = app_state.conversation.getMessages();
                            if (app_state.scroll_offset + 1 < messages.len) {
                                app_state.scroll_offset += 1;
                            }
                        } else if (key.matches(vaxis.Key.home, .{})) {
                            // Home: Scroll to top
                            app_state.scroll_offset = 0;
                        } else if (key.matches(vaxis.Key.end, .{})) {
                            // End: Scroll to bottom
                            const messages = app_state.conversation.getMessages();
                            app_state.scroll_offset = if (messages.len > 0) messages.len - 1 else 0;
                        } else if (key.matches(vaxis.Key.enter, .{})) {
                            // Enter: Submit input
                            if (app_state.input_buffer.items.len > 0) {
                                try handleUserInput(&app_state, allocator);
                                // Auto-scroll to bottom on new message
                                app_state.scroll_offset = 0;
                            }
                        } else if (key.matches(vaxis.Key.backspace, .{})) {
                            // Backspace: Delete character
                            if (app_state.input_buffer.items.len > 0) {
                                _ = app_state.input_buffer.pop();
                            }
                        } else if (key.codepoint != 0 and std.ascii.isPrint(@intCast(key.codepoint))) {
                            // Printable character: Add to buffer
                            try app_state.input_buffer.append(@intCast(key.codepoint));
                        }
                    }
                },
                .winsize => |ws| {
                    try vx.resize(allocator, tty.writer(), ws);
                },
                else => {},
            }
        }

        // Render
        const win = vx.window();
        win.clear();
        try layout.draw(win, &app_state);
        try vx.render(tty.writer());
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    foo: u8,
};

fn handleUserInput(state: *App.AppState, allocator: std.mem.Allocator) !void {
    // Submit input to conversation
    try state.submitInput();

    // Call agent loop
    try agentLoop(state, allocator);
}

fn agentLoop(state: *App.AppState, allocator: std.mem.Allocator) !void {
    var continue_loop = true;

    while (continue_loop) {
        continue_loop = false;

        // Get LLM response with streaming
        const messages = state.conversation.getMessages();

        // Buffer for collecting streamed response
        var response_buffer = std.array_list.AlignedManaged(u8, null).init(allocator);
        defer response_buffer.deinit();

        // Set streaming flag
        state.is_streaming = true;

        // Stream callback context
        const StreamContext = struct {
            buffer: *std.array_list.AlignedManaged(u8, null),
        };

        var stream_ctx = StreamContext{
            .buffer = &response_buffer,
        };

        const streamCallback = struct {
            fn onChunk(chunk: api_common.StreamChunk, user_data: ?*anyopaque) void {
                const ctx = @as(*StreamContext, @ptrCast(@alignCast(user_data.?)));
                if (!chunk.is_done and chunk.content.len > 0) {
                    ctx.buffer.appendSlice(chunk.content) catch return;
                    // TODO: Trigger UI re-render here in future
                }
            }
        }.onChunk;

        // Stream the response
        state.api_client.streamMessage(messages, streamCallback, &stream_ctx) catch |err| {
            state.is_streaming = false;
            const error_msg = try std.fmt.allocPrint(
                allocator,
                "[Error] Failed to get LLM response: {s}",
                .{@errorName(err)},
            );
            defer allocator.free(error_msg);
            try state.conversation.append(.assistant, error_msg);
            return;
        };

        state.is_streaming = false;

        const response = try response_buffer.toOwnedSlice();
        defer allocator.free(response);

        // Add assistant response to conversation
        try state.conversation.append(.assistant, response);

        // Parse tool invocations
        const invocations = try parser.extractToolInvocations(response, allocator);
        defer {
            for (invocations) |*inv| {
                inv.deinit();
            }
            allocator.free(invocations);
        }

        if (invocations.len == 0) {
            // No tools to execute, we're done
            return;
        }

        // Execute tools
        for (invocations) |inv| {
            // Check if tool is allowed in current mode
            if (!tools.ToolRegistry.isToolAllowed(inv.tool_name, state.current_mode)) {
                const error_msg = try std.fmt.allocPrint(
                    allocator,
                    "[Error] {s} is not available in {s} mode. Switch to BUILD mode with Tab to make file changes.",
                    .{ inv.tool_name, @tagName(state.current_mode) },
                );
                defer allocator.free(error_msg);

                try state.conversation.append(.tool_result, error_msg);
                continue;
            }

            // Get tool from registry
            const tool_info = state.tool_registry.get(inv.tool_name);
            if (tool_info == null) {
                const error_msg = try std.fmt.allocPrint(
                    allocator,
                    "[Error] Unknown tool: {s}",
                    .{inv.tool_name},
                );
                defer allocator.free(error_msg);
                try state.conversation.append(.tool_result, error_msg);
                continue;
            }

            // Execute tool
            const result = tool_info.?.function(inv.args, allocator) catch |err| {
                const error_msg = try std.fmt.allocPrint(
                    allocator,
                    "[Error] Tool execution failed: {s}",
                    .{@errorName(err)},
                );
                defer allocator.free(error_msg);
                try state.conversation.append(.tool_result, error_msg);
                continue;
            };

            // Serialize result to JSON
            const result_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(result.data, .{})});
            defer allocator.free(result_json);

            // Add tool result to conversation
            const tool_result_msg = try std.fmt.allocPrint(
                allocator,
                "tool_result({s})",
                .{result_json},
            );
            defer allocator.free(tool_result_msg);

            try state.conversation.append(.tool_result, tool_result_msg);
        }

        // Continue loop since we executed tools
        continue_loop = true;
    }
}

fn handleModalInput(state: *App.AppState, key: vaxis.Key, allocator: std.mem.Allocator) !void {
    // Build modal items to determine bounds
    const items = try modal_view.buildModalItems(state, allocator);
    defer allocator.free(items);

    if (items.len == 0) {
        // No providers configured, close modal
        state.closeModal();
        return;
    }

    if (key.matches(vaxis.Key.escape, .{})) {
        // Esc: Close modal
        state.closeModal();
    } else if (key.matches(vaxis.Key.up, .{})) {
        // Up: Move cursor up
        if (state.modal_cursor > 0) {
            state.modal_cursor -= 1;
        }
    } else if (key.matches(vaxis.Key.down, .{})) {
        // Down: Move cursor down
        if (state.modal_cursor < items.len - 1) {
            state.modal_cursor += 1;
        }
    } else if (key.matches(vaxis.Key.enter, .{})) {
        // Enter: Select item
        const selected_item = items[state.modal_cursor];

        if (selected_item.model) |model| {
            // Model selected - switch provider and model
            try state.switchProviderAndModel(selected_item.provider, model);
        } else {
            // Provider header selected - toggle expansion
            if (state.modal_expanded_provider) |expanded| {
                if (expanded == selected_item.provider) {
                    // Collapse this provider
                    state.modal_expanded_provider = null;
                } else {
                    // Expand this provider
                    state.modal_expanded_provider = selected_item.provider;
                }
            } else {
                // Expand this provider
                state.modal_expanded_provider = selected_item.provider;
            }
        }
    }
}
