const std = @import("std");
const read_file = @import("read_file");
const list_files = @import("list_files");
const edit_file = @import("edit_file");
const testing = std.testing;

test "read_file returns file content" {
    const allocator = testing.allocator;

    // Create a temporary test file
    const test_content = "Hello, World!\nThis is a test file.";
    const test_file_path = "test_read_file.txt";

    // Write test file
    {
        const file = try std.fs.cwd().createFile(test_file_path, .{});
        defer file.close();
        try file.writeAll(test_content);
    }
    defer std.fs.cwd().deleteFile(test_file_path) catch {};

    // Test read_file tool
    const tool = read_file.getTool();
    const args_json = try std.fmt.allocPrint(allocator, "{{\"filename\": \"{s}\"}}", .{test_file_path});
    defer allocator.free(args_json);

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = try tool.function(args.value, allocator);
    defer {
        if (result.data == .object) {
            if (result.data.object.get("content")) |content_val| {
                if (content_val == .string) {
                    allocator.free(content_val.string);
                }
            }
        }
    }

    try testing.expect(result.data == .object);
    const obj = result.data.object;
    try testing.expect(obj.get("content") != null);
    try testing.expectEqualStrings(test_content, obj.get("content").?.string);
}

test "read_file handles non-existent file" {
    const allocator = testing.allocator;

    const tool = read_file.getTool();
    const args_json = "{\"filename\": \"non_existent_file_12345.txt\"}";

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = tool.function(args.value, allocator) catch |err| {
        // Should return an error
        try testing.expect(err == error.FileNotFound or err == error.AccessDenied);
        return;
    };

    // If no error, check that result indicates failure
    defer {
        if (result.data == .object) {
            if (result.data.object.get("error")) |error_val| {
                if (error_val == .string) {
                    allocator.free(error_val.string);
                }
            }
        }
    }

    try testing.expect(result.data == .object);
}

test "list_files returns directory listing" {
    const allocator = testing.allocator;

    // Create a temporary directory with test files
    const test_dir = "test_list_dir";
    try std.fs.cwd().makeDir(test_dir);
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // Create test files
    {
        const file1 = try std.fs.cwd().createFile(test_dir ++ "/file1.txt", .{});
        file1.close();

        const file2 = try std.fs.cwd().createFile(test_dir ++ "/file2.txt", .{});
        file2.close();

        try std.fs.cwd().makeDir(test_dir ++ "/subdir");
    }

    // Test list_files tool
    const tool = list_files.getTool();
    const args_json = try std.fmt.allocPrint(allocator, "{{\"path\": \"{s}\"}}", .{test_dir});
    defer allocator.free(args_json);

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = try tool.function(args.value, allocator);
    defer {
        if (result.data == .object) {
            if (result.data.object.get("files")) |files_val| {
                if (files_val == .array) {
                    for (files_val.array.items) |item| {
                        if (item == .object) {
                            if (item.object.get("name")) |name| {
                                if (name == .string) allocator.free(name.string);
                            }
                            if (item.object.get("type")) |type_val| {
                                if (type_val == .string) allocator.free(type_val.string);
                            }
                        }
                    }
                    files_val.array.deinit();
                }
            }
        }
    }

    try testing.expect(result.data == .object);
    const obj = result.data.object;
    try testing.expect(obj.get("files") != null);
    try testing.expect(obj.get("files").? == .array);

    // Should have at least 3 entries (file1.txt, file2.txt, subdir)
    const files_array = obj.get("files").?.array;
    try testing.expect(files_array.items.len >= 3);
}

test "edit_file replaces text" {
    const allocator = testing.allocator;

    // Create a test file
    const test_file = "test_edit_file.txt";
    const original_content = "Hello World\nThis is original text\nGoodbye";

    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll(original_content);
    }
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Test edit_file tool
    const tool = edit_file.getTool();
    const args_json = try std.fmt.allocPrint(
        allocator,
        "{{\"path\": \"{s}\", \"old_str\": \"original\", \"new_str\": \"modified\"}}",
        .{test_file},
    );
    defer allocator.free(args_json);

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = try tool.function(args.value, allocator);
    defer {
        if (result.data == .object) {
            if (result.data.object.get("action")) |action| {
                if (action == .string) allocator.free(action.string);
            }
        }
    }

    try testing.expect(result.data == .object);
    const obj = result.data.object;
    try testing.expect(obj.get("action") != null);
    try testing.expectEqualStrings("edited", obj.get("action").?.string);

    // Verify file was modified
    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();

    const modified_content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(modified_content);

    try testing.expect(std.mem.indexOf(u8, modified_content, "modified") != null);
    try testing.expect(std.mem.indexOf(u8, modified_content, "original") == null);
}

test "edit_file creates new file" {
    const allocator = testing.allocator;

    const test_file = "test_create_file.txt";
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Test edit_file tool with empty old_str
    const tool = edit_file.getTool();
    const args_json = try std.fmt.allocPrint(
        allocator,
        "{{\"path\": \"{s}\", \"old_str\": \"\", \"new_str\": \"Brand new file content\"}}",
        .{test_file},
    );
    defer allocator.free(args_json);

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = try tool.function(args.value, allocator);
    defer {
        if (result.data == .object) {
            if (result.data.object.get("action")) |action| {
                if (action == .string) allocator.free(action.string);
            }
        }
    }

    try testing.expect(result.data == .object);
    const obj = result.data.object;
    try testing.expectEqualStrings("created_file", obj.get("action").?.string);

    // Verify file exists
    const file = try std.fs.cwd().openFile(test_file, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    try testing.expectEqualStrings("Brand new file content", content);
}

test "edit_file handles old_str not found" {
    const allocator = testing.allocator;

    const test_file = "test_edit_not_found.txt";
    const original_content = "Hello World";

    {
        const file = try std.fs.cwd().createFile(test_file, .{});
        defer file.close();
        try file.writeAll(original_content);
    }
    defer std.fs.cwd().deleteFile(test_file) catch {};

    // Try to replace text that doesn't exist
    const tool = edit_file.getTool();
    const args_json = try std.fmt.allocPrint(
        allocator,
        "{{\"path\": \"{s}\", \"old_str\": \"NonExistent\", \"new_str\": \"replacement\"}}",
        .{test_file},
    );
    defer allocator.free(args_json);

    const args = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer args.deinit();

    const result = tool.function(args.value, allocator) catch |err| {
        // Should return an error
        try testing.expect(err == error.OldStringNotFound or err == error.StringNotFound);
        return;
    };

    // If no error, result should indicate the string was not found
    defer {
        if (result.data == .object) {
            if (result.data.object.get("error")) |error_val| {
                if (error_val == .string) allocator.free(error_val.string);
            }
        }
    }

    try testing.expect(result.data == .object);
}
