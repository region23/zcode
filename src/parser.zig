const std = @import("std");

pub const ToolInvocation = struct {
    tool_name: []const u8,
    args: std.json.Value,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ToolInvocation) void {
        self.allocator.free(self.tool_name);
        // Note: args.deinit() should be called by the caller if needed
    }
};

/// Extract tool invocations from LLM response text
/// Format: "tool: TOOL_NAME({JSON_ARGS})"
pub fn extractToolInvocations(text: []const u8, allocator: std.mem.Allocator) ![]ToolInvocation {
    var invocations = std.array_list.AlignedManaged(ToolInvocation, null).init(allocator);
    errdefer {
        for (invocations.items) |*inv| {
            inv.deinit();
        }
        invocations.deinit();
    }

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");

        // Check if line starts with "tool:"
        if (!std.mem.startsWith(u8, line, "tool:")) continue;

        // Parse: "tool: name({...})"
        const after_colon = std.mem.trim(u8, line[5..], " ");

        const paren_idx = std.mem.indexOf(u8, after_colon, "(");
        if (paren_idx == null) continue;

        const name_part = std.mem.trim(u8, after_colon[0..paren_idx.?], " ");
        const name = try allocator.dupe(u8, name_part);
        errdefer allocator.free(name);

        const json_start = paren_idx.? + 1;
        const json_end_idx = std.mem.lastIndexOf(u8, after_colon, ")");
        if (json_end_idx == null) {
            allocator.free(name);
            continue;
        }

        const json_str = after_colon[json_start..json_end_idx.?];

        // Parse JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json_str,
            .{},
        ) catch |err| {
            // If JSON parsing fails, skip this invocation
            std.debug.print("Failed to parse JSON for tool {s}: {}\n", .{ name, err });
            allocator.free(name);
            continue;
        };

        try invocations.append(.{
            .tool_name = name,
            .args = parsed.value,
            .allocator = allocator,
        });
    }

    return invocations.toOwnedSlice();
}

/// Check if text contains any tool invocations
pub fn hasToolInvocations(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (std.mem.startsWith(u8, line, "tool:")) {
            return true;
        }
    }
    return false;
}

test "extract single tool invocation" {
    const allocator = std.testing.allocator;

    const text = "Let me read that file.\ntool: read_file({\"filename\": \"test.txt\"})\n";

    const invocations = try extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try std.testing.expectEqual(@as(usize, 1), invocations.len);
    try std.testing.expectEqualStrings("read_file", invocations[0].tool_name);
}

test "extract multiple tool invocations" {
    const allocator = std.testing.allocator;

    const text =
        \\I'll help you with that.
        \\tool: list_files({"path": "."})
        \\After listing, I'll read the file.
        \\tool: read_file({"filename": "test.txt"})
        \\Done!
    ;

    const invocations = try extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try std.testing.expectEqual(@as(usize, 2), invocations.len);
    try std.testing.expectEqualStrings("list_files", invocations[0].tool_name);
    try std.testing.expectEqualStrings("read_file", invocations[1].tool_name);
}

test "ignore non-tool lines" {
    const allocator = std.testing.allocator;

    const text =
        \\This is just regular text.
        \\No tools here!
        \\Just explaining the code.
    ;

    const invocations = try extractToolInvocations(text, allocator);
    defer allocator.free(invocations);

    try std.testing.expectEqual(@as(usize, 0), invocations.len);
}

test "has tool invocations" {
    try std.testing.expect(hasToolInvocations("tool: read_file({\"filename\": \"test.txt\"})"));
    try std.testing.expect(!hasToolInvocations("Just regular text without any tools"));
}
