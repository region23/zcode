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
        const request_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(std.json.Value{ .object = request_obj }, .{})});
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // Prepare headers
        const headers = [_]std.http.Header{
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
            .{ .name = "Content-Type", .value = "application/json" },
        };

        // Create request
        const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");
        var req = try http_client.request(.POST, uri, .{
            .extra_headers = &headers,
        });
        defer req.deinit();

        // Send request body
        req.transfer_encoding = .{ .content_length = request_json.len };
        var buffer: [4096]u8 = undefined;
        var body_writer = try req.sendBodyUnflushed(&buffer);
        try body_writer.writer.writeAll(request_json);
        try body_writer.end();
        try req.connection.?.flush();

        // Receive response
        var redirect_buffer: [1024]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        var transfer_buffer: [4096]u8 = undefined;
        const io_reader = response.reader(&transfer_buffer);

        const response_body = try io_reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024));
        defer allocator.free(response_body);

        // Parse response JSON
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            response_body,
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
        const request_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(std.json.Value{ .object = request_obj }, .{})});
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // Prepare headers
        const headers = [_]std.http.Header{
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
            .{ .name = "Content-Type", .value = "application/json" },
        };

        // Create request
        const uri = try std.Uri.parse("https://api.anthropic.com/v1/messages");
        var req = try http_client.request(.POST, uri, .{
            .extra_headers = &headers,
        });
        defer req.deinit();

        // Send request body
        req.transfer_encoding = .{ .content_length = request_json.len };
        var buffer: [4096]u8 = undefined;
        var body_writer = try req.sendBodyUnflushed(&buffer);
        try body_writer.writer.writeAll(request_json);
        try body_writer.end();
        try req.connection.?.flush();

        // Receive response
        var redirect_buffer: [1024]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        var transfer_buffer: [4096]u8 = undefined;
        const io_reader = response.reader(&transfer_buffer);

        // Read entire response (TODO: implement true SSE streaming)
        const response_body = try io_reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024));
        defer allocator.free(response_body);

        // Parse SSE chunks from buffered response
        var parser = streaming.SSEParser.init(allocator);
        defer parser.deinit();

        // Process response to simulate streaming
        if (try parser.parseChunk(response_body)) |event| {
            defer event.deinit(allocator);

            if (event.content) |content| {
                callback(.{ .content = content, .is_done = false }, user_data);
            }
        }

        // Final done callback
        callback(.{ .content = "", .is_done = true }, user_data);
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *AnthropicClient = @ptrCast(@alignCast(ctx));
        self.allocator.free(self.api_key);
        self.allocator.free(self.model);
        self.allocator.destroy(self);
    }
};
