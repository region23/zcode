const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");
const api_common = @import("../api/common.zig");

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
            .user => .{ .index = 4 }, // Blue
            .assistant => .{ .index = 3 }, // Yellow
            .tool_result => .{ .index = 5 }, // Magenta
            .system => .{ .index = 2 }, // Green
        };

        // Role prefix
        const role_prefix = switch (msg.role) {
            .user => "You: ",
            .assistant => "Assistant: ",
            .tool_result => "[Tool Result] ",
            .system => "[System] ",
        };

        const style = vaxis.Style{
            .fg = fg_color,
        };

        // Print role prefix
        var child = win.child(.{
            .x_off = 0,
            .y_off = y,
            .width = .{ .limit = win.width },
            .height = .{ .limit = 1 },
        });

        var prefix_segment = vaxis.Segment{
            .text = role_prefix,
            .style = style,
        };
        _ = try child.printSegment(prefix_segment, .{});

        // Print content (simple version - no word wrap yet)
        var content_segment = vaxis.Segment{
            .text = msg.content,
            .style = .{},
        };
        _ = try child.printSegment(content_segment, .{});

        y += 1;

        // Add blank line between messages for readability
        y += 1;
    }
}
