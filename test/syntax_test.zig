const std = @import("std");
const syntax = @import("syntax");
const testing = std.testing;

test "detect Zig keywords" {
    const allocator = testing.allocator;

    const code = "const x: u32 = 42; fn main() void {}";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    // Should find keywords "const" and "fn"
    var found_const = false;
    var found_fn = false;

    for (tokens) |token| {
        if (std.mem.eql(u8, token.text, "const") and token.type == .keyword) {
            found_const = true;
        }
        if (std.mem.eql(u8, token.text, "fn") and token.type == .keyword) {
            found_fn = true;
        }
    }

    try testing.expect(found_const);
    try testing.expect(found_fn);
}

test "detect Python keywords" {
    const allocator = testing.allocator;

    const code = "def hello(): return 42";
    const tokens = try syntax.tokenize(code, .python, allocator);
    defer allocator.free(tokens);

    var found_def = false;
    var found_return = false;

    for (tokens) |token| {
        if (std.mem.eql(u8, token.text, "def") and token.type == .keyword) {
            found_def = true;
        }
        if (std.mem.eql(u8, token.text, "return") and token.type == .keyword) {
            found_return = true;
        }
    }

    try testing.expect(found_def);
    try testing.expect(found_return);
}

test "detect JavaScript keywords" {
    const allocator = testing.allocator;

    const code = "const x = async () => { return await fetch(); }";
    const tokens = try syntax.tokenize(code, .javascript, allocator);
    defer allocator.free(tokens);

    var found_const = false;
    var found_async = false;
    var found_await = false;

    for (tokens) |token| {
        if (std.mem.eql(u8, token.text, "const") and token.type == .keyword) {
            found_const = true;
        }
        if (std.mem.eql(u8, token.text, "async") and token.type == .keyword) {
            found_async = true;
        }
        if (std.mem.eql(u8, token.text, "await") and token.type == .keyword) {
            found_await = true;
        }
    }

    try testing.expect(found_const);
    try testing.expect(found_async);
    try testing.expect(found_await);
}

test "detect string literals" {
    const allocator = testing.allocator;

    const code = "const msg = \"Hello World\";";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    var found_string = false;
    for (tokens) |token| {
        if (token.type == .string and std.mem.indexOf(u8, token.text, "Hello") != null) {
            found_string = true;
            break;
        }
    }

    try testing.expect(found_string);
}

test "detect numbers" {
    const allocator = testing.allocator;

    const code = "const x = 42; const y = 3.14;";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    var number_count: usize = 0;
    for (tokens) |token| {
        if (token.type == .number) {
            number_count += 1;
        }
    }

    try testing.expect(number_count >= 2);
}

test "detect comments in Zig" {
    const allocator = testing.allocator;

    const code = "// This is a comment\nconst x = 42;";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    var found_comment = false;
    for (tokens) |token| {
        if (token.type == .comment) {
            found_comment = true;
            break;
        }
    }

    try testing.expect(found_comment);
}

test "detect comments in Python" {
    const allocator = testing.allocator;

    const code = "# This is a comment\nx = 42";
    const tokens = try syntax.tokenize(code, .python, allocator);
    defer allocator.free(tokens);

    var found_comment = false;
    for (tokens) |token| {
        if (token.type == .comment) {
            found_comment = true;
            break;
        }
    }

    try testing.expect(found_comment);
}

test "detect code blocks in markdown" {
    const allocator = testing.allocator;

    const markdown =
        \\Here is some Zig code:
        \\```zig
        \\const x = 42;
        \\```
        \\
        \\And some Python:
        \\```python
        \\def hello():
        \\    print("Hi")
        \\```
    ;

    const blocks = try syntax.detectCodeBlocks(markdown, allocator);
    defer {
        for (blocks) |block| {
            allocator.free(block.code);
        }
        allocator.free(blocks);
    }

    try testing.expectEqual(@as(usize, 2), blocks.len);
    try testing.expectEqual(syntax.Language.zig, blocks[0].language);
    try testing.expectEqual(syntax.Language.python, blocks[1].language);

    try testing.expect(std.mem.indexOf(u8, blocks[0].code, "const x = 42") != null);
    try testing.expect(std.mem.indexOf(u8, blocks[1].code, "def hello") != null);
}

test "detect code block without language" {
    const allocator = testing.allocator;

    const markdown =
        \\Some code:
        \\```
        \\generic code here
        \\```
    ;

    const blocks = try syntax.detectCodeBlocks(markdown, allocator);
    defer {
        for (blocks) |block| {
            allocator.free(block.code);
        }
        allocator.free(blocks);
    }

    try testing.expectEqual(@as(usize, 1), blocks.len);
    try testing.expectEqual(syntax.Language.unknown, blocks[0].language);
}

test "language detection from string" {
    try testing.expectEqual(syntax.Language.zig, syntax.Language.fromString("zig"));
    try testing.expectEqual(syntax.Language.python, syntax.Language.fromString("python"));
    try testing.expectEqual(syntax.Language.python, syntax.Language.fromString("py"));
    try testing.expectEqual(syntax.Language.javascript, syntax.Language.fromString("javascript"));
    try testing.expectEqual(syntax.Language.javascript, syntax.Language.fromString("js"));
    try testing.expectEqual(syntax.Language.json, syntax.Language.fromString("json"));
    try testing.expectEqual(syntax.Language.unknown, syntax.Language.fromString("unknown"));
}

test "JSON tokenization" {
    const allocator = testing.allocator;

    const json_code = "{\"name\": \"test\", \"value\": 123, \"active\": true}";
    const tokens = try syntax.tokenize(json_code, .json, allocator);
    defer allocator.free(tokens);

    var found_string = false;
    var found_number = false;
    var found_keyword = false;

    for (tokens) |token| {
        if (token.type == .string) found_string = true;
        if (token.type == .number) found_number = true;
        if (token.type == .keyword and std.mem.eql(u8, token.text, "true")) {
            found_keyword = true;
        }
    }

    try testing.expect(found_string);
    try testing.expect(found_number);
    try testing.expect(found_keyword);
}

test "detect type names in Zig" {
    const allocator = testing.allocator;

    const code = "const MyStruct = struct {};";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    var found_type = false;
    for (tokens) |token| {
        if (std.mem.eql(u8, token.text, "MyStruct") and token.type == .type_name) {
            found_type = true;
            break;
        }
    }

    try testing.expect(found_type);
}

test "empty code returns minimal tokens" {
    const allocator = testing.allocator;

    const code = "";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    // Empty code should return no tokens or just plain text
    try testing.expect(tokens.len <= 1);
}

test "whitespace preservation" {
    const allocator = testing.allocator;

    const code = "const   x   =   42;";
    const tokens = try syntax.tokenize(code, .zig, allocator);
    defer allocator.free(tokens);

    // Should have whitespace tokens
    var has_whitespace = false;
    for (tokens) |token| {
        if (token.type == .plain and std.mem.indexOf(u8, token.text, " ") != null) {
            has_whitespace = true;
            break;
        }
    }

    try testing.expect(has_whitespace);
}
