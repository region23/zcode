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

fn executeReadFile(args: std.json.Value, allocator: std.mem.Allocator) !registry.ToolResult {
    // Extract filename from args
    const filename = blk: {
        if (args != .object) return error.InvalidArguments;
        const obj = args.object;
        const filename_value = obj.get("filename") orelse return error.MissingFilename;
        if (filename_value != .string) return error.InvalidFilenameType;
        break :blk filename_value.string;
    };

    // Resolve to absolute path
    const abs_path = try resolveAbsolutePath(filename, allocator);
    defer allocator.free(abs_path);

    // Read file
    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        // Return error as tool result
        var result_obj = std.json.ObjectMap.init(allocator);
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to read file: {s}", .{@errorName(err)});
        try result_obj.put("error", .{ .string = error_msg });
        try result_obj.put("file_path", .{ .string = try allocator.dupe(u8, abs_path) });

        return registry.ToolResult{
            .success = false,
            .data = .{ .object = result_obj },
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // Max 10MB

    // Build result
    var result_obj = std.json.ObjectMap.init(allocator);
    try result_obj.put("file_path", .{ .string = try allocator.dupe(u8, abs_path) });
    try result_obj.put("content", .{ .string = content });

    return registry.ToolResult{
        .success = true,
        .data = .{ .object = result_obj },
    };
}

pub fn getTool() registry.ToolInfo {
    return registry.ToolInfo{
        .name = "read_file",
        .description = "Gets the full content of a file provided by the user.",
        .parameters = &[_]registry.ParameterInfo{
            .{
                .name = "filename",
                .type_name = "string",
                .description = "The name of the file to read (absolute or relative path)",
                .required = true,
            },
        },
        .function = executeReadFile,
    };
}
