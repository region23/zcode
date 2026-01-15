const std = @import("std");
const config = @import("../config.zig");

pub const ParameterInfo = struct {
    name: []const u8,
    type_name: []const u8,
    description: []const u8,
    required: bool,
};

pub const ToolResult = struct {
    success: bool,
    data: std.json.Value,

    pub fn deinit(self: ToolResult, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    switch (entry.value_ptr.*) {
                        .string => |s| allocator.free(s),
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
};

pub const ToolFunction = *const fn (args: std.json.Value, allocator: std.mem.Allocator) anyerror!ToolResult;

pub const ToolInfo = struct {
    name: []const u8,
    description: []const u8,
    parameters: []const ParameterInfo,
    function: ToolFunction,
};

pub const ToolRegistry = struct {
    tools: std.StringHashMap(ToolInfo),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ToolRegistry {
        return .{
            .tools = std.StringHashMap(ToolInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn register(self: *ToolRegistry, tool: ToolInfo) !void {
        try self.tools.put(tool.name, tool);
    }

    pub fn get(self: *ToolRegistry, name: []const u8) ?ToolInfo {
        return self.tools.get(name);
    }

    pub fn deinit(self: *ToolRegistry) void {
        self.tools.deinit();
    }

    /// Generate system prompt with available tools based on mode
    pub fn generateSystemPrompt(self: *ToolRegistry, mode: config.Mode, allocator: std.mem.Allocator) ![]const u8 {
        var list = std.ArrayList(u8).init(allocator);
        const writer = list.writer();

        try writer.writeAll(
            \\You are a coding assistant whose goal it is to help us solve coding tasks.
            \\You have access to a series of tools you can execute. Here are the tools you can execute:
            \\
            \\
        );

        var iter = self.tools.iterator();
        while (iter.next()) |entry| {
            const tool = entry.value_ptr.*;

            // Skip edit_file in plan mode
            if (mode == .plan and std.mem.eql(u8, tool.name, "edit_file")) {
                continue;
            }

            try writer.writeAll("TOOL\n");
            try writer.writeAll("===============\n");
            try writer.print("Name: {s}\n", .{tool.name});
            try writer.print("Description: {s}\n", .{tool.description});
            try writer.writeAll("Parameters:\n");

            for (tool.parameters) |param| {
                const required_str = if (param.required) "required" else "optional";
                try writer.print("  - {s} ({s}, {s}): {s}\n", .{
                    param.name,
                    param.type_name,
                    required_str,
                    param.description,
                });
            }

            try writer.writeAll("===============\n\n");
        }

        try writer.writeAll(
            \\
            \\When you want to use a tool, reply with exactly one line in the format: 'tool: TOOL_NAME({{JSON_ARGS}})' and nothing else.
            \\Use compact single-line JSON with double quotes. After receiving a tool_result(...) message, continue the task.
            \\If no tool is needed, respond normally.
            \\
        );

        return list.toOwnedSlice();
    }

    /// Check if a tool is allowed in the current mode
    pub fn isToolAllowed(tool_name: []const u8, mode: config.Mode) bool {
        if (mode == .plan and std.mem.eql(u8, tool_name, "edit_file")) {
            return false;
        }
        return true;
    }
};
