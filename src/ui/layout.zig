const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");
const status_bar = @import("status_bar.zig");
const chat_view = @import("chat_view.zig");
const input_view = @import("input_view.zig");
const modal_view = @import("modal_view.zig");

pub fn draw(win: vaxis.Window, state: *App.AppState) !void {
    const height = win.height;
    const width = win.width;

    // Status bar (top 1 row)
    const status_win = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = width,
        .height = 1,
    });
    try status_bar.draw(status_win, state);

    // Separator line
    const separator_win = win.child(.{
        .x_off = 0,
        .y_off = 1,
        .width = width,
        .height = 1,
    });
    separator_win.clear();
    var i: usize = 0;
    while (i < width) : (i += 1) {
const segment = vaxis.Segment{
            .text = "─",
            .style = .{ .fg = .{ .index = 8 } }, // Gray
        };
        _ = separator_win.printSegment(segment, .{});
    }

    // Chat view (middle, scrollable)
    const chat_height = if (height > 6) height - 6 else 1; // Reserve space for status, separators, input, hints
    const chat_win = win.child(.{
        .x_off = 0,
        .y_off = 2,
        .width = width,
        .height = chat_height,
    });
    try chat_view.draw(chat_win, state);

    // Separator before input
    const input_sep_y = 2 + chat_height;
    if (input_sep_y < height) {
        const input_sep_win = win.child(.{
            .x_off = 0,
            .y_off = input_sep_y,
            .width = width,
            .height = 1,
        });
        input_sep_win.clear();
        i = 0;
        while (i < width) : (i += 1) {
const segment = vaxis.Segment{
                .text = "─",
                .style = .{ .fg = .{ .index = 8 } },
            };
            _ = input_sep_win.printSegment(segment, .{});
        }
    }

    // Input field (bottom, 1 row)
    const input_y = input_sep_y + 1;
    if (input_y < height) {
        const input_win = win.child(.{
            .x_off = 0,
            .y_off = input_y,
            .width = width,
            .height = 1,
        });
        try input_view.draw(input_win, state);
    }

    // Key hints (bottom, 1 row)
    const hints_y = input_y + 1;
    if (hints_y < height) {
        const hints_win = win.child(.{
            .x_off = 0,
            .y_off = hints_y,
            .width = width,
            .height = 1,
        });
        hints_win.clear();

        const hints_style = vaxis.Style{
            .fg = .{ .index = 8 }, // Gray
        };

const hints_segment = vaxis.Segment{
            .text = " Tab: Mode | Ctrl+P: Model | Ctrl+L: Clear | PgUp/PgDn: Scroll | Ctrl+Q: Quit",
            .style = hints_style,
        };
        _ = hints_win.printSegment(hints_segment, .{});
    }

    // Modal overlay (if shown)
    if (state.show_modal) {
        try modal_view.draw(win, state);
    }
}
