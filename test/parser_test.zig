const std = @import("std");
const parser = @import("parser");
const testing = std.testing;

test "extract single tool invocation" {
    const text =
        \\I'll read the file for you.
        \\tool: read_file({"filename": "test.txt"})
        \\
        \\The file contains important data.
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 1), invocations.len);
    try testing.expectEqualStrings("read_file", invocations[0].tool_name);

    // Verify args can be parsed as JSON
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, invocations[0].args, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try testing.expect(obj.get("filename") != null);
    try testing.expectEqualStrings("test.txt", obj.get("filename").?.string);
}

test "extract multiple tool invocations" {
    const text =
        \\First, I'll list the directory.
        \\tool: list_files({"path": "."})
        \\
        \\Now I'll read the config file.
        \\tool: read_file({"filename": "config.json"})
        \\
        \\Done!
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 2), invocations.len);
    try testing.expectEqualStrings("list_files", invocations[0].tool_name);
    try testing.expectEqualStrings("read_file", invocations[1].tool_name);
}

test "no tool invocations" {
    const text =
        \\This is just a regular response.
        \\No tools are called here.
        \\Just explaining the concept.
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer allocator.free(invocations);

    try testing.expectEqual(@as(usize, 0), invocations.len);
}

test "tool invocation with nested objects" {
    const text =
        \\tool: edit_file({"path": "src/main.zig", "old_str": "hello", "new_str": "world"})
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 1), invocations.len);
    try testing.expectEqualStrings("edit_file", invocations[0].tool_name);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, invocations[0].args, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const obj = parsed.value.object;
    try testing.expectEqualStrings("src/main.zig", obj.get("path").?.string);
    try testing.expectEqualStrings("hello", obj.get("old_str").?.string);
    try testing.expectEqualStrings("world", obj.get("new_str").?.string);
}

test "malformed JSON in tool call" {
    const text =
        \\tool: read_file({broken json here})
    ;

    const allocator = testing.allocator;
    // Should return empty array on malformed JSON rather than crashing
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    // Parser should skip malformed invocations
    try testing.expectEqual(@as(usize, 0), invocations.len);
}

test "tool invocation with multiline JSON" {
    const text =
        \\tool: edit_file({
        \\  "path": "test.txt",
        \\  "old_str": "",
        \\  "new_str": "Hello World"
        \\})
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 1), invocations.len);
    try testing.expectEqualStrings("edit_file", invocations[0].tool_name);
}

test "tool name with underscores" {
    const text =
        \\tool: my_custom_tool({"arg": "value"})
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 1), invocations.len);
    try testing.expectEqualStrings("my_custom_tool", invocations[0].tool_name);
}

test "empty JSON object in tool call" {
    const text =
        \\tool: list_files({})
    ;

    const allocator = testing.allocator;
    const invocations = try parser.extractToolInvocations(text, allocator);
    defer {
        for (invocations) |*inv| {
            inv.deinit();
        }
        allocator.free(invocations);
    }

    try testing.expectEqual(@as(usize, 1), invocations.len);
    try testing.expectEqualStrings("list_files", invocations[0].tool_name);
    try testing.expectEqualStrings("{}", invocations[0].args);
}
