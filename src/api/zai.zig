const std = @import("std");
const client = @import("client.zig");
const common = @import("common.zig");
const streaming = @import("streaming.zig");

/// Z.AI client - OpenAI-compatible API
pub const ZAIClient = struct {
    api_key: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,
    max_tokens: usize,

    const vtable = client.ApiClientVTable{
        .sendMessage = sendMessageImpl,
        .streamMessage = streamMessageImpl,
        .deinit = deinitImpl,
    };

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8, max_tokens: usize) !*ZAIClient {
        const self = try allocator.create(ZAIClient);
        self.* = .{
            .api_key = try allocator.dupe(u8, api_key),
            .model = try allocator.dupe(u8, model),
            .allocator = allocator,
            .max_tokens = max_tokens,
        };
        return self;
    }

    pub fn asApiClient(self: *ZAIClient) client.ApiClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn buildRequestBody(self: *ZAIClient, messages: []const common.Message, stream: bool, allocator: std.mem.Allocator) ![]u8 {
        var request_obj = std.json.ObjectMap.init(allocator);
        defer request_obj.deinit();

        try request_obj.put("model", .{ .string = self.model });
        try request_obj.put("max_tokens", .{ .integer = @intCast(self.max_tokens) });
        if (stream) {
            try request_obj.put("stream", .{ .bool = true });
        }

        var messages_array = std.json.Array.init(allocator);
        defer messages_array.deinit();

        for (messages) |msg| {
            var msg_obj = std.json.ObjectMap.init(allocator);
            try msg_obj.put("role", .{ .string = msg.role.toString() });
            try msg_obj.put("content", .{ .string = msg.content });
            try messages_array.append(.{ .object = msg_obj });
        }

        try request_obj.put("messages", .{ .array = messages_array });

        return try std.json.stringifyAlloc(allocator, std.json.Value{ .object = request_obj }, .{});
    }

    fn sendMessageImpl(ctx: *anyopaque, messages: []const common.Message, allocator: std.mem.Allocator) ![]u8 {
        const self: *ZAIClient = @ptrCast(@alignCast(ctx));

        const request_json = try self.buildRequestBody(messages, false, allocator);
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // Z.AI endpoint
        const uri = try std.Uri.parse("https://api.z.ai/api/paas/v4/chat/completions");

        var headers = std.http.Headers.init(allocator);
        defer headers.deinit();

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        try headers.append("Authorization", auth_header);
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

        const max_response_size = 10 * 1024 * 1024;
        try request.reader().readAllArrayList(&response_body, max_response_size);

        // Parse response (OpenAI-compatible format)
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
                        std.debug.print("Z.AI API Error: {s}\n", .{msg_val.string});
                        return error.ApiError;
                    }
                }
            }
            return error.ApiError;
        }

        // Extract content
        const choices = response_obj.get("choices") orelse return error.MissingChoices;
        if (choices != .array or choices.array.items.len == 0) return error.InvalidChoices;

        const first_choice = choices.array.items[0];
        if (first_choice != .object) return error.InvalidChoice;

        const message = first_choice.object.get("message") orelse return error.MissingMessage;
        if (message != .object) return error.InvalidMessage;

        const content = message.object.get("content") orelse return error.MissingContent;
        if (content != .string) return error.InvalidContent;

        return try allocator.dupe(u8, content.string);
    }

    fn streamMessageImpl(
        ctx: *anyopaque,
        messages: []const common.Message,
        callback: common.StreamCallback,
        user_data: ?*anyopaque,
    ) !void {
        const self: *ZAIClient = @ptrCast(@alignCast(ctx));
        const allocator = self.allocator;

        const request_json = try self.buildRequestBody(messages, true, allocator);
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        const uri = try std.Uri.parse("https://api.z.ai/api/paas/v4/chat/completions");

        var headers = std.http.Headers.init(allocator);
        defer headers.deinit();

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        try headers.append("Authorization", auth_header);
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
        const self: *ZAIClient = @ptrCast(@alignCast(ctx));
        self.allocator.free(self.api_key);
        self.allocator.free(self.model);
        self.allocator.destroy(self);
    }
};
