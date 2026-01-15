const std = @import("std");
const client = @import("client.zig");
const common = @import("common.zig");
const streaming = @import("streaming.zig");

pub const AnthropicClient = struct {
    api_key: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,
    max_tokens: usize,

    const vtable = client.ApiClientVTable{
        .sendMessage = sendMessageImpl,
        .streamMessage = streamMessageImpl,
        .deinit = deinitImpl,
    };

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8, max_tokens: usize) !*AnthropicClient {
        const self = try allocator.create(AnthropicClient);
        self.* = .{
            .api_key = try allocator.dupe(u8, api_key),
            .model = try allocator.dupe(u8, model),
            .allocator = allocator,
            .max_tokens = max_tokens,
        };
        return self;
    }

    pub fn asApiClient(self: *AnthropicClient) client.ApiClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn sendMessageImpl(ctx: *anyopaque, messages: []const common.Message, allocator: std.mem.Allocator) ![]u8 {
        const self: *AnthropicClient = @ptrCast(@alignCast(ctx));

        // Build request body
        var request_obj = std.json.ObjectMap.init(allocator);
        defer request_obj.deinit();

        try request_obj.put("model", .{ .string = self.model });
        try request_obj.put("max_tokens", .{ .integer = @intCast(self.max_tokens) });

        // Convert messages to Anthropic format
        // Anthropic separates system messages from user/assistant messages
        var system_content: ?[]const u8 = null;
        var messages_array = std.json.Array.init(allocator);
        defer messages_array.deinit();

        for (messages) |msg| {
            if (msg.role == .system) {
                system_content = msg.content;
            } else {
                var msg_obj = std.json.ObjectMap.init(allocator);
                const role_str = switch (msg.role) {
                    .user => "user",
                    .assistant => "assistant",
                    .tool_result => "user", // Tool results as user messages
                    .system => "user", // Shouldn't happen due to check above
                };
                try msg_obj.put("role", .{ .string = role_str });
                try msg_obj.put("content", .{ .string = msg.content });
                try messages_array.append(.{ .object = msg_obj });
            }
        }

        if (system_content) |sys| {
            try request_obj.put("system", .{ .string = sys });
        }

        try request_obj.put("messages", .{ .array = messages_array });

        // Serialize to JSON
        const request_json = try std.json.stringifyAlloc(allocator, std.json.Value{ .object = request_obj }, .{});
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // Prepare request
        const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");

        var headers = std.http.Headers.init(allocator);
        defer headers.deinit();

        try headers.append("x-api-key", self.api_key);
        try headers.append("anthropic-version", "2023-06-01");
        try headers.append("Content-Type", "application/json");

        var request = try http_client.open(.POST, uri, .{
            .server_header_buffer = try allocator.alloc(u8, 8192),
            .headers = headers,
        });
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = request_json.len };

        try request.send();
        try request.writeAll(request_json);
        try request.finish();

        try request.wait();

        // Read response
        var response_body = std.ArrayList(u8).init(allocator);
        defer response_body.deinit();

        const max_response_size = 10 * 1024 * 1024; // 10MB
        try request.reader().readAllArrayList(&response_body, max_response_size);

        // Parse response JSON
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            response_body.items,
            .{},
        );
        defer parsed.deinit();

        if (parsed.value != .object) return error.InvalidResponse;
        const response_obj = parsed.value.object;

        // Check for error
        if (response_obj.get("error")) |error_val| {
            if (error_val == .object) {
                if (error_val.object.get("message")) |msg_val| {
                    if (msg_val == .string) {
                        std.debug.print("Anthropic API Error: {s}\n", .{msg_val.string});
                        return error.ApiError;
                    }
                }
            }
            return error.ApiError;
        }

        // Extract content from response
        const content_arr = response_obj.get("content") orelse return error.MissingContent;
        if (content_arr != .array or content_arr.array.items.len == 0) return error.InvalidContent;

        const first_content = content_arr.array.items[0];
        if (first_content != .object) return error.InvalidContentBlock;

        const text = first_content.object.get("text") orelse return error.MissingText;
        if (text != .string) return error.InvalidText;

        return try allocator.dupe(u8, text.string);
    }

    fn streamMessageImpl(
        ctx: *anyopaque,
        messages: []const common.Message,
        callback: common.StreamCallback,
        user_data: ?*anyopaque,
    ) !void {
        const self: *AnthropicClient = @ptrCast(@alignCast(ctx));
        const allocator = self.allocator;

        // Build request body with streaming enabled
        var request_obj = std.json.ObjectMap.init(allocator);
        defer request_obj.deinit();

        try request_obj.put("model", .{ .string = self.model });
        try request_obj.put("max_tokens", .{ .integer = @intCast(self.max_tokens) });
        try request_obj.put("stream", .{ .bool = true });

        // Convert messages to Anthropic format
        var system_content: ?[]const u8 = null;
        var messages_array = std.json.Array.init(allocator);
        defer messages_array.deinit();

        for (messages) |msg| {
            if (msg.role == .system) {
                system_content = msg.content;
            } else {
                var msg_obj = std.json.ObjectMap.init(allocator);
                const role_str = switch (msg.role) {
                    .user => "user",
                    .assistant => "assistant",
                    .tool_result => "user",
                    .system => "user",
                };
                try msg_obj.put("role", .{ .string = role_str });
                try msg_obj.put("content", .{ .string = msg.content });
                try messages_array.append(.{ .object = msg_obj });
            }
        }

        if (system_content) |sys| {
            try request_obj.put("system", .{ .string = sys });
        }

        try request_obj.put("messages", .{ .array = messages_array });

        // Serialize to JSON
        const request_json = try std.json.stringifyAlloc(allocator, std.json.Value{ .object = request_obj }, .{});
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // Prepare request
        const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");

        var headers = std.http.Headers.init(allocator);
        defer headers.deinit();

        try headers.append("x-api-key", self.api_key);
        try headers.append("anthropic-version", "2023-06-01");
        try headers.append("Content-Type", "application/json");

        var request = try http_client.open(.POST, uri, .{
            .server_header_buffer = try allocator.alloc(u8, 8192),
            .headers = headers,
        });
        defer request.deinit();

        request.transfer_encoding = .{ .content_length = request_json.len };

        try request.send();
        try request.writeAll(request_json);
        try request.finish();

        try request.wait();

        // Stream response
        var parser = streaming.SSEParser.init(allocator);
        defer parser.deinit();

        var read_buffer: [4096]u8 = undefined;
        const reader = request.reader();

        while (true) {
            const bytes_read = reader.read(&read_buffer) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };

            if (bytes_read == 0) break;

            const chunk_data = read_buffer[0..bytes_read];

            // Parse chunk
            if (try parser.parseChunk(chunk_data)) |event| {
                defer event.deinit(allocator);

                if (event.is_done) {
                    callback(.{ .content = "", .is_done = true }, user_data);
                    break;
                }

                if (event.content) |content| {
                    callback(.{ .content = content, .is_done = false }, user_data);
                }
            }
        }
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *AnthropicClient = @ptrCast(@alignCast(ctx));
        self.allocator.free(self.api_key);
        self.allocator.free(self.model);
        self.allocator.destroy(self);
    }
};
