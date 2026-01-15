const std = @import("std");
const vaxis = @import("vaxis");

pub const TokenType = enum {
    keyword,
    string,
    number,
    comment,
    function_name,
    type_name,
    operator,
    identifier,
    plain,
};

pub const Token = struct {
    text: []const u8,
    type: TokenType,
};

pub const Language = enum {
    zig,
    python,
    javascript,
    json,
    unknown,

    pub fn fromString(lang: []const u8) Language {
        if (std.mem.eql(u8, lang, "zig")) return .zig;
        if (std.mem.eql(u8, lang, "python") or std.mem.eql(u8, lang, "py")) return .python;
        if (std.mem.eql(u8, lang, "javascript") or std.mem.eql(u8, lang, "js")) return .javascript;
        if (std.mem.eql(u8, lang, "json")) return .json;
        return .unknown;
    }
};

/// Get vaxis style for a token type
pub fn getTokenStyle(token_type: TokenType) vaxis.Style {
    return switch (token_type) {
        .keyword => .{ .fg = .{ .index = 12 } }, // Blue
        .string => .{ .fg = .{ .index = 10 } }, // Green
        .number => .{ .fg = .{ .index = 14 } }, // Cyan
        .comment => .{ .fg = .{ .index = 8 } }, // Gray
        .function_name => .{ .fg = .{ .index = 13 } }, // Magenta
        .type_name => .{ .fg = .{ .index = 11 } }, // Yellow
        .operator => .{ .fg = .{ .index = 9 } }, // Red
        .identifier => .{ .fg = .{ .index = 15 } }, // White
        .plain => .{ .fg = .{ .index = 7 } }, // Normal white
    };
}

/// Tokenize code based on language
pub fn tokenize(code: []const u8, lang: Language, allocator: std.mem.Allocator) ![]Token {
    return switch (lang) {
        .zig => tokenizeZig(code, allocator),
        .python => tokenizePython(code, allocator),
        .javascript => tokenizeJavaScript(code, allocator),
        .json => tokenizeJson(code, allocator),
        .unknown => tokenizePlain(code, allocator),
    };
}

fn tokenizePlain(code: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);
    try tokens.append(.{ .text = code, .type = .plain });
    return tokens.toOwnedSlice();
}

fn tokenizeZig(code: []const u8, allocator: std.mem.Allocator) ![]Token {
    const keywords = [_][]const u8{
        "const",  "var",      "fn",       "pub",     "return",  "if",
        "else",   "while",    "for",      "switch",  "try",     "catch",
        "defer",  "errdefer", "struct",   "enum",    "union",   "error",
        "break",  "continue", "comptime", "inline",  "export",  "extern",
        "usingnamespace", "test", "and", "or", "null", "undefined", "true", "false",
    };

    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);
    var i: usize = 0;

    while (i < code.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(code[i])) {
            const start = i;
            while (i < code.len and std.ascii.isWhitespace(code[i])) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .plain });
            continue;
        }

        // Comments
        if (i + 1 < code.len and code[i] == '/' and code[i + 1] == '/') {
            const start = i;
            while (i < code.len and code[i] != '\n') : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .comment });
            continue;
        }

        // String literals
        if (code[i] == '"') {
            const start = i;
            i += 1;
            while (i < code.len and code[i] != '"') {
                if (code[i] == '\\' and i + 1 < code.len) i += 1;
                i += 1;
            }
            if (i < code.len) i += 1; // Include closing quote
            try tokens.append(.{ .text = code[start..i], .type = .string });
            continue;
        }

        // Character literals
        if (code[i] == '\'') {
            const start = i;
            i += 1;
            while (i < code.len and code[i] != '\'') {
                if (code[i] == '\\' and i + 1 < code.len) i += 1;
                i += 1;
            }
            if (i < code.len) i += 1;
            try tokens.append(.{ .text = code[start..i], .type = .string });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(code[i])) {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '.' or code[i] == '_')) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .number });
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(code[i]) or code[i] == '_' or code[i] == '@') {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '_')) : (i += 1) {}
            const word = code[start..i];

            // Check if it's a keyword
            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, word, kw)) {
                    is_keyword = true;
                    break;
                }
            }

            const token_type: TokenType = if (is_keyword)
                .keyword
            else if (word.len > 0 and std.ascii.isUpper(word[0]))
                .type_name
            else
                .identifier;

            try tokens.append(.{ .text = word, .type = token_type });
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        try tokens.append(.{ .text = code[start..i], .type = .operator });
    }

    return tokens.toOwnedSlice();
}

fn tokenizePython(code: []const u8, allocator: std.mem.Allocator) ![]Token {
    const keywords = [_][]const u8{
        "def",    "class",  "if",     "elif",   "else",   "for",
        "while",  "return", "import", "from",   "as",     "try",
        "except", "finally", "with",  "lambda", "pass",   "break",
        "continue", "raise", "yield", "async", "await", "True", "False", "None",
        "and", "or", "not", "in", "is",
    };

    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);
    var i: usize = 0;

    while (i < code.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(code[i])) {
            const start = i;
            while (i < code.len and std.ascii.isWhitespace(code[i])) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .plain });
            continue;
        }

        // Comments
        if (code[i] == '#') {
            const start = i;
            while (i < code.len and code[i] != '\n') : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .comment });
            continue;
        }

        // String literals (single or double quotes, with triple quote support)
        if (code[i] == '"' or code[i] == '\'') {
            const quote = code[i];
            const start = i;
            i += 1;

            // Check for triple quotes
            if (i + 1 < code.len and code[i] == quote and code[i + 1] == quote) {
                i += 2;
                while (i + 2 < code.len) {
                    if (code[i] == quote and code[i + 1] == quote and code[i + 2] == quote) {
                        i += 3;
                        break;
                    }
                    i += 1;
                }
            } else {
                while (i < code.len and code[i] != quote) {
                    if (code[i] == '\\' and i + 1 < code.len) i += 1;
                    i += 1;
                }
                if (i < code.len) i += 1;
            }
            try tokens.append(.{ .text = code[start..i], .type = .string });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(code[i])) {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '.' or code[i] == '_')) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .number });
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(code[i]) or code[i] == '_') {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '_')) : (i += 1) {}
            const word = code[start..i];

            // Check if it's a keyword
            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, word, kw)) {
                    is_keyword = true;
                    break;
                }
            }

            // Check if followed by '(' for function call
            const is_function = i < code.len and code[i] == '(';

            const token_type: TokenType = if (is_keyword)
                .keyword
            else if (is_function)
                .function_name
            else if (word.len > 0 and std.ascii.isUpper(word[0]))
                .type_name
            else
                .identifier;

            try tokens.append(.{ .text = word, .type = token_type });
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        try tokens.append(.{ .text = code[start..i], .type = .operator });
    }

    return tokens.toOwnedSlice();
}

fn tokenizeJavaScript(code: []const u8, allocator: std.mem.Allocator) ![]Token {
    const keywords = [_][]const u8{
        "const",   "let",      "var",     "function", "return",  "if",
        "else",    "for",      "while",   "do",       "switch",  "case",
        "break",   "continue", "try",     "catch",    "finally", "throw",
        "class",   "extends",  "import",  "export",   "from",    "async",
        "await",   "new",      "this",    "typeof",   "instanceof", "true",
        "false",   "null",     "undefined", "yield",  "static",  "super",
    };

    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);
    var i: usize = 0;

    while (i < code.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(code[i])) {
            const start = i;
            while (i < code.len and std.ascii.isWhitespace(code[i])) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .plain });
            continue;
        }

        // Single-line comments
        if (i + 1 < code.len and code[i] == '/' and code[i + 1] == '/') {
            const start = i;
            while (i < code.len and code[i] != '\n') : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .comment });
            continue;
        }

        // Multi-line comments
        if (i + 1 < code.len and code[i] == '/' and code[i + 1] == '*') {
            const start = i;
            i += 2;
            while (i + 1 < code.len) {
                if (code[i] == '*' and code[i + 1] == '/') {
                    i += 2;
                    break;
                }
                i += 1;
            }
            try tokens.append(.{ .text = code[start..i], .type = .comment });
            continue;
        }

        // String literals
        if (code[i] == '"' or code[i] == '\'' or code[i] == '`') {
            const quote = code[i];
            const start = i;
            i += 1;
            while (i < code.len and code[i] != quote) {
                if (code[i] == '\\' and i + 1 < code.len) i += 1;
                i += 1;
            }
            if (i < code.len) i += 1;
            try tokens.append(.{ .text = code[start..i], .type = .string });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(code[i])) {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '.' or code[i] == '_')) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .number });
            continue;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(code[i]) or code[i] == '_' or code[i] == '$') {
            const start = i;
            while (i < code.len and (std.ascii.isAlphanumeric(code[i]) or code[i] == '_' or code[i] == '$')) : (i += 1) {}
            const word = code[start..i];

            var is_keyword = false;
            for (keywords) |kw| {
                if (std.mem.eql(u8, word, kw)) {
                    is_keyword = true;
                    break;
                }
            }

            const is_function = i < code.len and code[i] == '(';

            const token_type: TokenType = if (is_keyword)
                .keyword
            else if (is_function)
                .function_name
            else if (word.len > 0 and std.ascii.isUpper(word[0]))
                .type_name
            else
                .identifier;

            try tokens.append(.{ .text = word, .type = token_type });
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        try tokens.append(.{ .text = code[start..i], .type = .operator });
    }

    return tokens.toOwnedSlice();
}

fn tokenizeJson(code: []const u8, allocator: std.mem.Allocator) ![]Token {
    var tokens = std.array_list.AlignedManaged(Token, null).init(allocator);
    var i: usize = 0;

    while (i < code.len) {
        // Skip whitespace
        if (std.ascii.isWhitespace(code[i])) {
            const start = i;
            while (i < code.len and std.ascii.isWhitespace(code[i])) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .plain });
            continue;
        }

        // String literals (keys and values)
        if (code[i] == '"') {
            const start = i;
            i += 1;
            while (i < code.len and code[i] != '"') {
                if (code[i] == '\\' and i + 1 < code.len) i += 1;
                i += 1;
            }
            if (i < code.len) i += 1;
            try tokens.append(.{ .text = code[start..i], .type = .string });
            continue;
        }

        // Numbers
        if (std.ascii.isDigit(code[i]) or code[i] == '-') {
            const start = i;
            if (code[i] == '-') i += 1;
            while (i < code.len and (std.ascii.isDigit(code[i]) or code[i] == '.' or code[i] == 'e' or code[i] == 'E' or code[i] == '+' or code[i] == '-')) : (i += 1) {}
            try tokens.append(.{ .text = code[start..i], .type = .number });
            continue;
        }

        // Keywords (true, false, null)
        if (std.ascii.isAlphabetic(code[i])) {
            const start = i;
            while (i < code.len and std.ascii.isAlphabetic(code[i])) : (i += 1) {}
            const word = code[start..i];

            const is_keyword = std.mem.eql(u8, word, "true") or
                std.mem.eql(u8, word, "false") or
                std.mem.eql(u8, word, "null");

            try tokens.append(.{
                .text = word,
                .type = if (is_keyword) .keyword else .identifier,
            });
            continue;
        }

        // Operators and punctuation
        const start = i;
        i += 1;
        try tokens.append(.{ .text = code[start..i], .type = .operator });
    }

    return tokens.toOwnedSlice();
}

/// Detect code blocks in markdown text
pub const CodeBlock = struct {
    language: Language,
    code: []const u8,
    start_line: usize,
    end_line: usize,
};

pub fn detectCodeBlocks(text: []const u8, allocator: std.mem.Allocator) ![]CodeBlock {
    var blocks = std.array_list.AlignedManaged(CodeBlock, null).init(allocator);
    var lines = std.mem.splitSequence(u8, text, "\n");

    var line_num: usize = 0;
    var in_code_block = false;
    var block_lang: Language = .unknown;
    var block_start: usize = 0;
    var block_lines = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer block_lines.deinit();

    while (lines.next()) |line| {
        defer line_num += 1;

        // Check for code fence
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "```")) {
            if (in_code_block) {
                // End of code block
                const code = try std.mem.join(allocator, "\n", block_lines.items);
                try blocks.append(.{
                    .language = block_lang,
                    .code = code,
                    .start_line = block_start,
                    .end_line = line_num,
                });
                block_lines.clearRetainingCapacity();
                in_code_block = false;
            } else {
                // Start of code block
                const fence_line = std.mem.trimLeft(u8, line, " \t");
                const lang_start = 3; // After ```
                const lang_str = std.mem.trim(u8, fence_line[lang_start..], " \t\r\n");
                block_lang = Language.fromString(lang_str);
                block_start = line_num + 1;
                in_code_block = true;
            }
        } else if (in_code_block) {
            try block_lines.append(line);
        }
    }

    return blocks.toOwnedSlice();
}
