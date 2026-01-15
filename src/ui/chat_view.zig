const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");
const api_common = @import("../api/common.zig");
const syntax = @import("syntax.zig");

pub fn draw(win: vaxis.Window, state: *const App.AppState) !void {
    win.clear();

    var y: usize = 0;
    const messages = state.conversation.getMessages();

    // Apply scroll offset
    var start_index: usize = 0;
    if (state.scroll_offset < messages.len) {
        start_index = state.scroll_offset;
    }

    for (messages[start_index..]) |msg| {
        if (y >= win.height) break;

        // Choose color based on role
        const fg_color: vaxis.Color = switch (msg.role) {
            .user => .{ .index = 12 }, // Blue
            .assistant => .{ .index = 11 }, // Yellow
            .tool_result => .{ .index = 13 }, // Magenta
            .system => .{ .index = 10 }, // Green
        };

        // Role prefix
        const role_prefix = switch (msg.role) {
            .user => "You: ",
            .assistant => "Assistant: ",
            .tool_result => "[Tool Result] ",
            .system => "[System] ",
        };

        const role_style = vaxis.Style{
            .fg = fg_color,
            .bold = true,
        };

        // Print role prefix on first line
        if (y < win.height) {
            var prefix_win = win.child(.{
                .x_off = 0,
                .y_off = @intCast(y),
                .width = win.width,
                .height = 1,
            });

const prefix_segment = vaxis.Segment{
                .text = role_prefix,
                .style = role_style,
            };
            _ = prefix_win.printSegment(prefix_segment, .{});
            y += 1;
        }

        // Render content with syntax highlighting for code blocks
        y = try renderContent(win, msg.content, y, state.allocator, msg.role);

        // Add blank line between messages for readability
        y += 1;
    }
}

fn renderContent(
    win: vaxis.Window,
    content: []const u8,
    start_y: usize,
    allocator: std.mem.Allocator,
    role: api_common.MessageRole,
) !usize {
    var y = start_y;

    // Check for error messages
    const is_error = std.mem.startsWith(u8, content, "[Error]");

    // For assistant messages, detect code blocks
    if (role == .assistant and !is_error) {
        const code_blocks = try syntax.detectCodeBlocks(content, allocator);
        defer {
            for (code_blocks) |block| {
                allocator.free(block.code);
            }
            allocator.free(code_blocks);
        }

        if (code_blocks.len > 0) {
            // Render content with code block highlighting
            var lines = std.mem.splitSequence(u8, content, "\n");
            var line_num: usize = 0;
            var current_block_idx: usize = 0;
            var in_code_block = false;

            while (lines.next()) |line| {
                defer line_num += 1;
                if (y >= win.height) break;

                // Check if we're entering a code block
                if (current_block_idx < code_blocks.len and
                    line_num == code_blocks[current_block_idx].start_line - 1)
                {
                    in_code_block = true;
                }

                // Check if we're exiting a code block
                if (in_code_block and current_block_idx < code_blocks.len and
                    line_num == code_blocks[current_block_idx].end_line)
                {
                    in_code_block = false;
                    current_block_idx += 1;
                    continue; // Skip closing fence
                }

                if (in_code_block and current_block_idx < code_blocks.len) {
                    // Render code line with syntax highlighting
                    const block = code_blocks[current_block_idx];
                    const tokens = try syntax.tokenize(line, block.language, allocator);
                    defer allocator.free(tokens);

                    var line_win = win.child(.{
                        .x_off = 2,
                        .y_off = @intCast(y),
                        .width = if (win.width > 2) win.width - 2 else 1,
                        .height = 1,
                    });

                    for (tokens) |token| {
                        const token_style = syntax.getTokenStyle(token.type);
const segment = vaxis.Segment{
                            .text = token.text,
                            .style = token_style,
                        };
                        _ = line_win.printSegment(segment, .{});
                    }
                    y += 1;
                } else if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "```")) {
                    // Render fence line in gray
                    var line_win = win.child(.{
                        .x_off = 0,
                        .y_off = @intCast(y),
                        .width = win.width,
                        .height = 1,
                    });

const segment = vaxis.Segment{
                        .text = line,
                        .style = .{ .fg = .{ .index = 8 } }, // Gray
                    };
                    _ = line_win.printSegment(segment, .{});
                    y += 1;
                } else {
                    // Regular text line
                    y = try renderPlainLine(win, line, y, .{});
                }
            }
            return y;
        }
    }

    // No code blocks or error - render as plain text with optional error styling
    const line_style = if (is_error)
        vaxis.Style{ .fg = .{ .index = 9 }, .bold = true } // Red for errors
    else
        vaxis.Style{};

    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (y >= win.height) break;
        y = try renderPlainLine(win, line, y, line_style);
    }

    return y;
}

fn renderPlainLine(win: vaxis.Window, line: []const u8, y: usize, style: vaxis.Style) !usize {
    if (y >= win.height) return y;

    var line_win = win.child(.{
        .x_off = 2,
        .y_off = @intCast(y),
        .width = if (win.width > 2) win.width - 2 else 1,
        .height = 1,
    });

const segment = vaxis.Segment{
        .text = line,
        .style = style,
    };
    _ = line_win.printSegment(segment, .{});

    return y + 1;
}
