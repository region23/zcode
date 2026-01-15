const std = @import("std");
const registry = @import("registry.zig");

/// Resolve relative path to absolute path
fn resolveAbsolutePath(path_str: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var path = std.fs.path.resolve(allocator, &[_][]const u8{path_str}) catch |err| {
        // If resolve fails, try to use cwd + path
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        return std.fs.path.join(allocator, &[_][]const u8{ cwd, path_str });
    };
    return path;
}

fn executeListFiles(args: std.json.Value, allocator: std.mem.Allocator) !registry.ToolResult {
    // Extract path from args (default to "." if not provided)
    const path_str = blk: {
        if (args != .object) break :blk ".";
        const obj = args.object;
        const path_value = obj.get("path");
        if (path_value) |val| {
            if (val != .string) return error.InvalidPathType;
            break :blk val.string;
        }
        break :blk ".";
    };

    // Resolve to absolute path
    const abs_path = try resolveAbsolutePath(path_str, allocator);
    defer allocator.free(abs_path);

    // Open directory
    const dir = std.fs.openDirAbsolute(abs_path, .{ .iterate = true }) catch |err| {
        // Return error as tool result
        var result_obj = std.json.ObjectMap.init(allocator);
        const error_msg = try std.fmt.allocPrint(allocator, "Failed to open directory: {s}", .{@errorName(err)});
        try result_obj.put("error", .{ .string = error_msg });
        try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });

        return registry.ToolResult{
            .success = false,
            .data = .{ .object = result_obj },
        };
    };
    defer dir.close();

    // Iterate directory
    var files_array = std.json.Array.init(allocator);
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        var file_obj = std.json.ObjectMap.init(allocator);

        const filename = try allocator.dupe(u8, entry.name);
        try file_obj.put("filename", .{ .string = filename });

        const file_type = switch (entry.kind) {
            .file => "file",
            .directory => "dir",
            .sym_link => "symlink",
            else => "other",
        };
        try file_obj.put("type", .{ .string = try allocator.dupe(u8, file_type) });

        try files_array.append(.{ .object = file_obj });
    }

    // Build result
    var result_obj = std.json.ObjectMap.init(allocator);
    try result_obj.put("path", .{ .string = try allocator.dupe(u8, abs_path) });
    try result_obj.put("files", .{ .array = files_array });

    return registry.ToolResult{
        .success = true,
        .data = .{ .object = result_obj },
    };
}

pub fn getTool() registry.ToolInfo {
    return registry.ToolInfo{
        .name = "list_files",
        .description = "Lists the files in a directory provided by the user.",
        .parameters = &[_]registry.ParameterInfo{
            .{
                .name = "path",
                .type_name = "string",
                .description = "The path to a directory to list files from (default: current directory)",
                .required = false,
            },
        },
        .function = executeListFiles,
    };
}
