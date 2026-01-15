const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");

pub fn draw(win: vaxis.Window, state: *const App.AppState) !void {
    win.clear();

    const prompt_style = vaxis.Style{
        .fg = .{ .index = 2 }, // Green
    };

    // Draw prompt
    var prompt_segment = vaxis.Segment{
        .text = "> ",
        .style = prompt_style,
    };
    _ = try win.printSegment(prompt_segment, .{});

    // Draw input buffer
    var input_segment = vaxis.Segment{
        .text = state.input_buffer.items,
        .style = .{},
    };
    _ = try win.printSegment(input_segment, .{});

    // Show cursor at the end of input
    // Note: Cursor positioning would be handled by vaxis
}
