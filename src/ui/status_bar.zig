const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");

pub fn draw(win: vaxis.Window, state: *const App.AppState) !void {
    // Clear the window with background color
    win.clear();

    const bg_style = vaxis.Style{
        .bg = .{ .index = 4 }, // Blue background
        .fg = .{ .index = 15 }, // White text
    };

    // Left section: [MODE] zcode
    const mode_str = state.getModeString();
    const left_text = try std.fmt.allocPrint(
        state.allocator,
        "{s} zcode",
        .{mode_str},
    );
    defer state.allocator.free(left_text);

    var left_segment = vaxis.Segment{
        .text = left_text,
        .style = bg_style,
    };
    _ = try win.printSegment(left_segment, .{});

    // Right section: Provider | Model [Streaming]
    const provider_name = @tagName(state.current_provider);
    const streaming_indicator = if (state.is_streaming) " [Streaming]" else "";

    const right_text = try std.fmt.allocPrint(
        state.allocator,
        "{s} | {s}{s}",
        .{ provider_name, state.current_model, streaming_indicator },
    );
    defer state.allocator.free(right_text);

    // Calculate position to right-align
    const padding = if (win.width > left_text.len + right_text.len)
        win.width - left_text.len - right_text.len
    else
        1;

    // Draw padding
    var i: usize = 0;
    while (i < padding) : (i += 1) {
        var space_segment = vaxis.Segment{
            .text = " ",
            .style = bg_style,
        };
        _ = try win.printSegment(space_segment, .{});
    }

    // Draw right text
    var right_segment = vaxis.Segment{
        .text = right_text,
        .style = bg_style,
    };
    _ = try win.printSegment(right_segment, .{});
}
