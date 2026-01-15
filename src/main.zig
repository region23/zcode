const std = @import("std");
const vaxis = @import("vaxis");
const config = @import("config.zig");
const App = @import("app.zig");
const layout = @import("ui/layout.zig");
const parser = @import("parser.zig");
const tools = @import("tools/registry.zig");

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
    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    // Main event loop
    var running = true;
    while (running) {
        loop.pollEvent();
        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| {
                    if (key.matches('c', .{ .ctrl = true })) {
                        // Ctrl+C: Clear conversation
                        app_state.clearConversation();
                    } else if (key.matches('q', .{ .ctrl = true })) {
                        // Ctrl+Q: Quit
                        running = false;
                    } else if (key.matches(vaxis.Key.tab, .{})) {
                        // Tab: Toggle mode
                        try app_state.toggleMode();
                    } else if (key.matches(vaxis.Key.enter, .{})) {
                        // Enter: Submit input
                        if (app_state.input_buffer.items.len > 0) {
                            try handleUserInput(&app_state, allocator);
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
                },
                .winsize => |ws| {
                    try vx.resize(allocator, tty.anyWriter(), ws);
                },
                else => {},
            }
        }

        // Render
        const win = vx.window();
        win.clear();
        try layout.draw(win, &app_state);
        try vx.render(tty.anyWriter());
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

        // Get LLM response
        const messages = state.conversation.getMessages();
        const response = state.api_client.sendMessage(messages, allocator) catch |err| {
            const error_msg = try std.fmt.allocPrint(
                allocator,
                "[Error] Failed to get LLM response: {s}",
                .{@errorName(err)},
            );
            defer allocator.free(error_msg);
            try state.conversation.append(.assistant, error_msg);
            return;
        };
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
            const result_json = try std.json.stringifyAlloc(allocator, result.data, .{});
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
