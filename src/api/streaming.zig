const std = @import("std");

pub const StreamEvent = struct {
    content: ?[]const u8,
    is_done: bool,

    pub fn deinit(self: StreamEvent, allocator: std.mem.Allocator) void {
        if (self.content) |c| {
            allocator.free(c);
        }
    }
};

pub const SSEParser = struct {
    buffer: std.array_list.AlignedManaged(u8, null),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SSEParser {
        return .{
            .buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SSEParser) void {
        self.buffer.deinit();
    }

    /// Parse a chunk of SSE data
    /// Returns null if the chunk is incomplete (needs more data)
    /// Returns StreamEvent if a complete event was parsed
    pub fn parseChunk(self: *SSEParser, data: []const u8) !?StreamEvent {
        // Append to buffer
        try self.buffer.appendSlice(data);

        // Look for complete SSE event (ends with \n\n)
        const buffer_str = self.buffer.items;
        const event_end = std.mem.indexOf(u8, buffer_str, "\n\n");
        if (event_end == null) {
            // Incomplete event, need more data
            return null;
        }

        // Extract complete event
        const event_str = buffer_str[0..event_end.?];
        defer {
            // Remove processed event from buffer
            const remaining = buffer_str[event_end.? + 2 ..];
            self.buffer.clearRetainingCapacity();
            self.buffer.appendSlice(remaining) catch {};
        }

        // Parse event lines
        var lines = std.mem.splitScalar(u8, event_str, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Check for "data: " prefix
            if (std.mem.startsWith(u8, trimmed, "data: ")) {
                const data_content = trimmed[6..]; // Skip "data: "

                // Check for [DONE] marker
                if (std.mem.eql(u8, data_content, "[DONE]")) {
                    return StreamEvent{
                        .content = null,
                        .is_done = true,
                    };
                }

                // Parse JSON to extract content
                const content = try self.extractContent(data_content);
                return StreamEvent{
                    .content = content,
                    .is_done = false,
                };
            }
        }

        // No data line found
        return null;
    }

    /// Extract content from JSON data
    /// Different providers have different JSON structures
    fn extractContent(self: *SSEParser, json_str: []const u8) !?[]const u8 {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json_str,
            .{},
        ) catch |err| {
            std.debug.print("Failed to parse JSON: {}\n", .{err});
            return null;
        };
        defer parsed.deinit();

        if (parsed.value != .object) return null;
        const obj = parsed.value.object;

        // Try OpenAI format: {"choices": [{"delta": {"content": "..."}}]}
        if (obj.get("choices")) |choices_val| {
            if (choices_val == .array and choices_val.array.items.len > 0) {
                const first_choice = choices_val.array.items[0];
                if (first_choice == .object) {
                    if (first_choice.object.get("delta")) |delta_val| {
                        if (delta_val == .object) {
                            if (delta_val.object.get("content")) |content_val| {
                                if (content_val == .string) {
                                    return try self.allocator.dupe(u8, content_val.string);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Try Anthropic format: {"type": "content_block_delta", "delta": {"text": "..."}}
        if (obj.get("type")) |type_val| {
            if (type_val == .string and std.mem.eql(u8, type_val.string, "content_block_delta")) {
                if (obj.get("delta")) |delta_val| {
                    if (delta_val == .object) {
                        if (delta_val.object.get("text")) |text_val| {
                            if (text_val == .string) {
                                return try self.allocator.dupe(u8, text_val.string);
                            }
                        }
                    }
                }
            }
        }

        // Try direct content field: {"content": "..."}
        if (obj.get("content")) |content_val| {
            if (content_val == .string) {
                return try self.allocator.dupe(u8, content_val.string);
            }
        }

        // Try text field: {"text": "..."}
        if (obj.get("text")) |text_val| {
            if (text_val == .string) {
                return try self.allocator.dupe(u8, text_val.string);
            }
        }

        return null;
    }

    /// Reset the parser state
    pub fn reset(self: *SSEParser) void {
        self.buffer.clearRetainingCapacity();
    }
};

test "parse OpenAI SSE chunk" {
    const allocator = std.testing.allocator;
    var parser = SSEParser.init(allocator);
    defer parser.deinit();

    const chunk = "data: {\"choices\": [{\"delta\": {\"content\": \"Hello\"}}]}\n\n";
    const event = try parser.parseChunk(chunk);

    try std.testing.expect(event != null);
    try std.testing.expect(event.?.content != null);
    try std.testing.expectEqualStrings("Hello", event.?.content.?);
    try std.testing.expect(!event.?.is_done);

    if (event.?.content) |c| {
        allocator.free(c);
    }
}

test "parse DONE marker" {
    const allocator = std.testing.allocator;
    var parser = SSEParser.init(allocator);
    defer parser.deinit();

    const chunk = "data: [DONE]\n\n";
    const event = try parser.parseChunk(chunk);

    try std.testing.expect(event != null);
    try std.testing.expect(event.?.content == null);
    try std.testing.expect(event.?.is_done);
}

test "handle incomplete chunk" {
    const allocator = std.testing.allocator;
    var parser = SSEParser.init(allocator);
    defer parser.deinit();

    // First part of event (no \n\n)
    const chunk1 = "data: {\"content\":";
    const event1 = try parser.parseChunk(chunk1);
    try std.testing.expect(event1 == null);

    // Second part completes the event
    const chunk2 = " \"Hello\"}\n\n";
    const event2 = try parser.parseChunk(chunk2);
    try std.testing.expect(event2 != null);

    if (event2) |e| {
        if (e.content) |c| {
            allocator.free(c);
        }
    }
}
