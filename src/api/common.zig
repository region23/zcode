const std = @import("std");

pub const MessageRole = enum {
    system,
    user,
    assistant,
    tool_result,

    pub fn toString(self: MessageRole) []const u8 {
        return switch (self) {
            .system => "system",
            .user => "user",
            .assistant => "assistant",
            .tool_result => "tool",
        };
    }
};

pub const Message = struct {
    role: MessageRole,
    content: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, role: MessageRole, content: []const u8) !Message {
        const owned_content = try allocator.dupe(u8, content);
        return Message{
            .role = role,
            .content = owned_content,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Message) void {
        self.allocator.free(self.content);
    }
};

pub const Conversation = struct {
    messages: std.array_list.AlignedManaged(Message, null),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Conversation {
        return .{
            .messages = std.array_list.AlignedManaged(Message, null).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn append(self: *Conversation, role: MessageRole, content: []const u8) !void {
        const message = try Message.init(self.allocator, role, content);
        try self.messages.append(message);
    }

    pub fn clear(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.clearRetainingCapacity();
    }

    pub fn deinit(self: *Conversation) void {
        for (self.messages.items) |*msg| {
            msg.deinit();
        }
        self.messages.deinit();
    }

    /// Get the last message in the conversation, if any
    pub fn getLastMessage(self: *const Conversation) ?*const Message {
        if (self.messages.items.len == 0) return null;
        return &self.messages.items[self.messages.items.len - 1];
    }

    /// Get all messages as a slice
    pub fn getMessages(self: *const Conversation) []const Message {
        return self.messages.items;
    }
};

/// Streaming chunk from API
pub const StreamChunk = struct {
    content: []const u8,
    is_done: bool,
};

/// Callback for streaming responses
pub const StreamCallback = *const fn (chunk: StreamChunk, user_data: ?*anyopaque) void;
