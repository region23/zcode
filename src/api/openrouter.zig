const std = @import("std");
const client = @import("client.zig");
const common = @import("common.zig");
const streaming = @import("streaming.zig");

/// OpenRouter client - Generic OpenAI-compatible API for multiple models
/// Supports DeepSeek, Qwen, and many other models
pub const OpenRouterClient = struct {
    api_key: []const u8,
    model: []const u8,
    allocator: std.mem.Allocator,
    max_tokens: usize,

    const vtable = client.ApiClientVTable{
        .sendMessage = sendMessageImpl,
        .streamMessage = streamMessageImpl,
        .deinit = deinitImpl,
    };

    pub fn init(allocator: std.mem.Allocator, api_key: []const u8, model: []const u8, max_tokens: usize) !*OpenRouterClient {
        const self = try allocator.create(OpenRouterClient);
        self.* = .{
            .api_key = try allocator.dupe(u8, api_key),
            .model = try allocator.dupe(u8, model),
            .allocator = allocator,
            .max_tokens = max_tokens,
        };
        return self;
    }

    pub fn asApiClient(self: *OpenRouterClient) client.ApiClient {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn buildRequestBody(self: *OpenRouterClient, messages: []const common.Message, stream: bool, allocator: std.mem.Allocator) ![]u8 {
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

        return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(std.json.Value{ .object = request_obj }, .{})});
    }

    fn sendMessageImpl(ctx: *anyopaque, messages: []const common.Message, allocator: std.mem.Allocator) ![]u8 {
        const self: *OpenRouterClient = @ptrCast(@alignCast(ctx));

        const request_json = try self.buildRequestBody(messages, false, allocator);
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        // OpenRouter endpoint
        const uri = try std.Uri.parse("https://openrouter.ai/api/v1/chat/completions");

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "HTTP-Referer", .value = "https://github.com/yourusername/zcode" },
            .{ .name = "X-Title", .value = "zcode" },
        };

        // Create request
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

        // Parse response (OpenAI-compatible format)
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
                        std.debug.print("OpenRouter API Error: {s}\n", .{msg_val.string});
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
        const self: *OpenRouterClient = @ptrCast(@alignCast(ctx));
        const allocator = self.allocator;

        const request_json = try self.buildRequestBody(messages, true, allocator);
        defer allocator.free(request_json);

        // Create HTTP client
        var http_client = std.http.Client{ .allocator = allocator };
        defer http_client.deinit();

        const uri = try std.Uri.parse("https://openrouter.ai/api/v1/chat/completions");

        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
        defer allocator.free(auth_header);

        const headers = [_]std.http.Header{
            .{ .name = "Authorization", .value = auth_header },
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "HTTP-Referer", .value = "https://github.com/yourusername/zcode" },
            .{ .name = "X-Title", .value = "zcode" },
        };

        var req = try http_client.request(.POST, uri, .{
            .extra_headers = &headers,
        });
        defer req.deinit();

        req.transfer_encoding = .{ .content_length = request_json.len };
        var buffer: [4096]u8 = undefined;
        var body_writer = try req.sendBodyUnflushed(&buffer);
        try body_writer.writer.writeAll(request_json);
        try body_writer.end();
        try req.connection.?.flush();

        var redirect_buffer: [1024]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        var transfer_buffer: [4096]u8 = undefined;
        const io_reader = response.reader(&transfer_buffer);

        const response_body = try io_reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024));
        defer allocator.free(response_body);

        var parser = streaming.SSEParser.init(allocator);
        defer parser.deinit();

        if (try parser.parseChunk(response_body)) |event| {
            defer event.deinit(allocator);

            if (event.content) |content| {
                callback(.{ .content = content, .is_done = false }, user_data);
            }
        }

        callback(.{ .content = "", .is_done = true }, user_data);
    }

    fn deinitImpl(ctx: *anyopaque) void {
        const self: *OpenRouterClient = @ptrCast(@alignCast(ctx));
        self.allocator.free(self.api_key);
        self.allocator.free(self.model);
        self.allocator.destroy(self);
    }
};
