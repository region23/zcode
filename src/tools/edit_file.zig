const std = @import("std");
const registry = @import("registry.zig");

/// Resolve relative path to absolute path
fn resolveAbsolutePath(path_str: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const path = std.fs.path.resolve(allocator, &[_][]const u8{path_str}) catch {
        // If resolve fails, try to use cwd + path
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        return std.fs.path.join(allocator, &[_][]const u8{ cwd, path_str });
    };
    return path;
}

fn executeEditFile(args: std.json.Value, allocator: std.mem.Allocator) !registry.ToolResult {
    // Extract arguments
    if (args != .object) return error.InvalidArguments;
    const obj = args.object;

    const path_str = blk: {
        const path_value = obj.get("path") orelse return error.MissingPath;
        if (path_value != .string) return error.InvalidPathType;
        break :blk path_value.string;
    };

    const old_str = blk: {
        const old_value = obj.get("old_str") orelse return error.MissingOldStr;
        if (old_value != .string) return error.InvalidOldStrType;
        break :blk old_value.string;
    };

    const new_str = blk: {
        const new_value = obj.get("new_str") orelse return error.MissingNewStr;
        if (new_value != .string) return error.InvalidNewStrType;
        break :blk new_value.string;
    };

    // Resolve to absolute path
    const abs_path = try resolveAbsolutePath(path_str, allocator);
    defer allocator.free(abs_path);

    // If old_str is empty, create/overwrite file
    if (old_str.len == 0) {
        const file = std.fs.createFileAbsolute(abs_path, .{}) catch |err| {
            var result_obj = std.json.ObjectMap.init(allocator);
            const error_msg = try std.fmt.allocPrint(allocator, "Failed to create file: {s}", .{@errorName(err)});
            try result_obj.put("error", .{ .string = error_msg });
            try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });

            return registry.ToolResult{
                .success = false,
                .data = .{ .object = result_obj },
            };
        };
        defer file.close();

        file.writeAll(new_str) catch |err| {
            var result_obj = std.json.ObjectMap.init(allocator);
            const error_msg = try std.fmt.allocPrint(allocator, "Failed to write file: {s}", .{@errorName(err)});
            try result_obj.put("error", .{ .string = error_msg });
            try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });

            return registry.ToolResult{
                .success = false,
                .data = .{ .object = result_obj },
            };
        };

        var result_obj = std.json.ObjectMap.init(allocator);
        try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });
        try result_obj.put("action", .{ .string = try allocator.dupe(u8, "created_file") });

        return registry.ToolResult{
            .success = true,
            .data = .{ .object = result_obj },
        };
    }

    // Read existing file
    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        var result_obj = std.json.ObjectMap.init(allocator);
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open file: {s}", .{@errorName(err)});
        try result_obj.put("error", .{ .string = error_msg });
        try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });

        return registry.ToolResult{
            .success = false,
            .data = .{ .object = result_obj },
        };
    };
    defer file.close();

    const original = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB
    defer allocator.free(original);

    // Find and replace first occurrence
    const index = std.mem.indexOf(u8, original, old_str);
    if (index == null) {
        var result_obj = std.json.ObjectMap.init(allocator);
        try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });
        try result_obj.put("action", .{ .string = try allocator.dupe(u8, "old_str not found") });
        try result_obj.put("error", .{ .string = try allocator.dupe(u8, "The specified old_str was not found in the file") });

        return registry.ToolResult{
            .success = false,
            .data = .{ .object = result_obj },
        };
    }

    // Create edited content
    const edited = try std.mem.concat(allocator, u8, &[_][]const u8{
        original[0..index.?],
        new_str,
        original[index.? + old_str.len ..],
    });
    defer allocator.free(edited);

    // Write back to file
    const write_file = std.fs.createFileAbsolute(abs_path, .{}) catch |err| {
        var result_obj = std.json.ObjectMap.init(allocator);
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to write file: {s}", .{@errorName(err)});
        try result_obj.put("error", .{ .string = error_msg });
        try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });

        return registry.ToolResult{
            .success = false,
            .data = .{ .object = result_obj },
        };
    };
    defer write_file.close();

    try write_file.writeAll(edited);

    var result_obj = std.json.ObjectMap.init(allocator);
    try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });
    try result_obj.put("action", .{ .string = try allocator.dupe(u8, "edited") });

    return registry.ToolResult{
        .success = true,
        .data = .{ .object = result_obj },
    };
}

pub fn getTool() registry.ToolInfo {
    return registry.ToolInfo{
        .name = "edit_file",
        .description = "Replaces first occurrence of old_str with new_str in file. If old_str is empty, create/overwrite file with new_str.",
        .parameters = &[_]registry.ParameterInfo{
            .{
                .name = "path",
                .type_name = "string",
                .description = "The path to the file to edit",
                .required = true,
            },
            .{
                .name = "old_str",
                .type_name = "string",
                .description = "The string to replace (empty to create new file)",
                .required = true,
            },
            .{
                .name = "new_str",
                .type_name = "string",
                .description = "The string to replace with",
                .required = true,
            },
        },
        .function = executeEditFile,
    };
}
