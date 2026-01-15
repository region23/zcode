const std = @import("std");
const vaxis = @import("vaxis");
const App = @import("../app.zig");
const config = @import("../config.zig");

/// Modal item represents either a provider header or a model entry
pub const ModalItem = struct {
    provider: config.ApiProvider,
    model: ?[]const u8, // null for provider headers
    is_default: bool,
};

/// Build the flattened list of modal items
pub fn buildModalItems(state: *const App.AppState, allocator: std.mem.Allocator) ![]ModalItem {
    var items = std.ArrayList(ModalItem).init(allocator);
    errdefer items.deinit();

    // Iterate through all providers
    const all_providers = [_]config.ApiProvider{
        .openai,
        .anthropic,
        .zai,
        .deepseek,
        .qwen,
        .openrouter,
    };

    for (all_providers) |provider| {
        // Only show providers with configured API keys
        if (state.config.getApiKey(provider) == null) continue;

        // Add provider header
        try items.append(.{
            .provider = provider,
            .model = null,
            .is_default = false,
        });

        // If this provider is expanded, add its models
        if (state.modal_expanded_provider) |expanded| {
            if (expanded == provider) {
                const models = try config.getAvailableModels(provider, allocator);
                const default_model = config.getDefaultModel(provider);

                for (models) |model| {
                    try items.append(.{
                        .provider = provider,
                        .model = model,
                        .is_default = std.mem.eql(u8, model, default_model),
                    });
                }
            }
        }
    }

    return items.toOwnedSlice();
}

pub fn draw(win: vaxis.Window, state: *App.AppState) !void {
    const allocator = state.allocator;

    // Modal dimensions
    const modal_width = @min(60, win.width - 4);
    const modal_height = @min(25, win.height - 4);
    const modal_x = (win.width - modal_width) / 2;
    const modal_y = (win.height - modal_height) / 2;

    // Create modal window
    const modal_win = win.child(.{
        .x_off = modal_x,
        .y_off = modal_y,
        .width = .{ .limit = modal_width },
        .height = .{ .limit = modal_height },
    });

    // Clear and draw border
    modal_win.clear();

    const border_style = vaxis.Style{
        .fg = .{ .index = 7 }, // White
        .bg = .{ .index = 0 }, // Black background
    };

    // Draw border
    try drawBorder(modal_win, border_style);

    // Title
    const title_win = modal_win.child(.{
        .x_off = 2,
        .y_off = 1,
        .width = .{ .limit = modal_width - 4 },
        .height = .{ .limit = 1 },
    });

    const title_style = vaxis.Style{
        .fg = .{ .index = 14 }, // Cyan
        .bg = .{ .index = 0 },
        .bold = true,
    };

const title_segment = vaxis.Segment{
        .text = "Select Provider & Model",
        .style = title_style,
    };
    _ = try title_win.printSegment(title_segment, .{});

    // Separator
    const sep_win = modal_win.child(.{
        .x_off = 1,
        .y_off = 2,
        .width = .{ .limit = modal_width - 2 },
        .height = .{ .limit = 1 },
    });

const sep_segment = vaxis.Segment{
        .text = "─",
        .style = border_style,
    };

    var i: usize = 0;
    while (i < modal_width - 2) : (i += 1) {
        _ = try sep_win.printSegment(sep_segment, .{});
    }

    // Build modal items
    const items = try buildModalItems(state, allocator);
    defer allocator.free(items);

    // Clamp cursor to valid range
    if (state.modal_cursor >= items.len and items.len > 0) {
        state.modal_cursor = items.len - 1;
    }

    // Content area
    const content_height = modal_height - 6; // Leave room for title, separators, hints
    const content_win = modal_win.child(.{
        .x_off = 2,
        .y_off = 3,
        .width = .{ .limit = modal_width - 4 },
        .height = .{ .limit = content_height },
    });

    // Calculate scroll offset to keep cursor visible
    const scroll_offset = if (state.modal_cursor >= content_height)
        state.modal_cursor - content_height + 1
    else
        0;

    // Draw items
    var row: usize = 0;
    var idx: usize = scroll_offset;
    while (idx < items.len and row < content_height) : (idx += 1) {
        const item = items[idx];
        const is_selected = (idx == state.modal_cursor);

        const item_win = content_win.child(.{
            .x_off = 0,
            .y_off = row,
            .width = .{ .limit = modal_width - 4 },
            .height = .{ .limit = 1 },
        });

        if (item.model) |model| {
            // Model item (indented)
            const style = vaxis.Style{
                .fg = if (is_selected) .{ .index = 0 } else .{ .index = 7 },
                .bg = if (is_selected) .{ .index = 7 } else .{ .index = 0 },
            };

            const prefix = if (is_selected) "> " else "  ";
            const default_marker = if (item.is_default) " (default)" else "";

            const text = try std.fmt.allocPrint(
                allocator,
                "{s}  • {s}{s}",
                .{ prefix, model, default_marker },
            );
            defer allocator.free(text);

const segment = vaxis.Segment{
                .text = text,
                .style = style,
            };
            _ = try item_win.printSegment(segment, .{});
        } else {
            // Provider header
            const style = vaxis.Style{
                .fg = if (is_selected) .{ .index = 0 } else .{ .index = 11 }, // Yellow
                .bg = if (is_selected) .{ .index = 11 } else .{ .index = 0 },
                .bold = true,
            };

            const prefix = if (is_selected) "> " else "  ";
            const provider_name = @tagName(item.provider);

            const text = try std.fmt.allocPrint(
                allocator,
                "{s}{s}",
                .{ prefix, provider_name },
            );
            defer allocator.free(text);

const segment = vaxis.Segment{
                .text = text,
                .style = style,
            };
            _ = try item_win.printSegment(segment, .{});
        }

        row += 1;
    }

    // Bottom separator
    const bottom_sep_win = modal_win.child(.{
        .x_off = 1,
        .y_off = modal_height - 3,
        .width = .{ .limit = modal_width - 2 },
        .height = .{ .limit = 1 },
    });

    i = 0;
    while (i < modal_width - 2) : (i += 1) {
        _ = try bottom_sep_win.printSegment(sep_segment, .{});
    }

    // Key hints
    const hints_win = modal_win.child(.{
        .x_off = 2,
        .y_off = modal_height - 2,
        .width = .{ .limit = modal_width - 4 },
        .height = .{ .limit = 1 },
    });

    const hints_style = vaxis.Style{
        .fg = .{ .index = 8 }, // Gray
        .bg = .{ .index = 0 },
    };

const hints_segment = vaxis.Segment{
        .text = "↑↓: Navigate | Enter: Select | Esc: Cancel",
        .style = hints_style,
    };
    _ = try hints_win.printSegment(hints_segment, .{});
}

fn drawBorder(win: vaxis.Window, style: vaxis.Style) !void {
    // Top border
    var top_win = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = .{ .limit = win.width },
        .height = .{ .limit = 1 },
    });

const corner_segment = vaxis.Segment{ .text = "┌", .style = style };
    _ = try top_win.printSegment(corner_segment, .{});

const horizontal_segment = vaxis.Segment{ .text = "─", .style = style };
    var i: usize = 1;
    while (i < win.width - 1) : (i += 1) {
        _ = try top_win.printSegment(horizontal_segment, .{});
    }

    corner_segment.text = "┐";
    _ = try top_win.printSegment(corner_segment, .{});

    // Sides
    var row: usize = 1;
    while (row < win.height - 1) : (row += 1) {
        const left_win = win.child(.{
            .x_off = 0,
            .y_off = row,
            .width = .{ .limit = 1 },
            .height = .{ .limit = 1 },
        });

const vertical_segment = vaxis.Segment{ .text = "│", .style = style };
        _ = try left_win.printSegment(vertical_segment, .{});

        const right_win = win.child(.{
            .x_off = win.width - 1,
            .y_off = row,
            .width = .{ .limit = 1 },
            .height = .{ .limit = 1 },
        });

        _ = try right_win.printSegment(vertical_segment, .{});
    }

    // Bottom border
    var bottom_win = win.child(.{
        .x_off = 0,
        .y_off = win.height - 1,
        .width = .{ .limit = win.width },
        .height = .{ .limit = 1 },
    });

    corner_segment.text = "└";
    _ = try bottom_win.printSegment(corner_segment, .{});

    i = 1;
    while (i < win.width - 1) : (i += 1) {
        _ = try bottom_win.printSegment(horizontal_segment, .{});
    }

    corner_segment.text = "┘";
    _ = try bottom_win.printSegment(corner_segment, .{});
}
