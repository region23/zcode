const std = @import("std");
const common = @import("common.zig");

pub const ApiClientVTable = struct {
    sendMessage: *const fn (ctx: *anyopaque, messages: []const common.Message, allocator: std.mem.Allocator) anyerror![]u8,
    streamMessage: *const fn (ctx: *anyopaque, messages: []const common.Message, callback: common.StreamCallback, user_data: ?*anyopaque) anyerror!void,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub const ApiClient = struct {
    ptr: *anyopaque,
    vtable: *const ApiClientVTable,

    pub fn sendMessage(self: ApiClient, messages: []const common.Message, allocator: std.mem.Allocator) ![]u8 {
        return self.vtable.sendMessage(self.ptr, messages, allocator);
    }

    pub fn streamMessage(self: ApiClient, messages: []const common.Message, callback: common.StreamCallback, user_data: ?*anyopaque) !void {
        return self.vtable.streamMessage(self.ptr, messages, callback, user_data);
    }

    pub fn deinit(self: ApiClient) void {
        self.vtable.deinit(self.ptr);
    }
};
