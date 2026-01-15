const std = @import("std");
const streaming = @import("streaming");
const testing = std.testing;

test "parse complete SSE event" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const sse_data =
        \\data: {"choices":[{"delta":{"content":"Hello"}}]}
        \\
        \\
    ;

    const event = try parser.parseChunk(sse_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expect(!evt.is_done);
        try testing.expect(evt.content != null);
        try testing.expectEqualStrings("Hello", evt.content.?);
    }
}

test "parse multiple SSE events" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n";
    const chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\" World\"}}]}\n\n";

    // First chunk
    const event1 = try parser.parseChunk(chunk1);
    try testing.expect(event1 != null);
    if (event1) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings("Hello", evt.content.?);
    }

    // Second chunk
    const event2 = try parser.parseChunk(chunk2);
    try testing.expect(event2 != null);
    if (event2) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings(" World", evt.content.?);
    }
}

test "parse DONE marker" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const sse_data =
        \\data: [DONE]
        \\
        \\
    ;

    const event = try parser.parseChunk(sse_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expect(evt.is_done);
        try testing.expect(evt.content == null or evt.content.?.len == 0);
    }
}

test "buffer incomplete event" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    // Incomplete event (missing final newline)
    const incomplete_chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"Hel";

    const event1 = try parser.parseChunk(incomplete_chunk);
    try testing.expect(event1 == null); // Should buffer, not return event

    // Complete the event
    const completion = "lo\"}}]}\n\n";
    const event2 = try parser.parseChunk(completion);
    try testing.expect(event2 != null);

    if (event2) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings("Hello", evt.content.?);
    }
}

test "parse Anthropic format" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const anthropic_data =
        \\data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello from Claude"}}
        \\
        \\
    ;

    const event = try parser.parseChunk(anthropic_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expect(!evt.is_done);
        try testing.expect(evt.content != null);
        try testing.expectEqualStrings("Hello from Claude", evt.content.?);
    }
}

test "parse empty content delta" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const sse_data =
        \\data: {"choices":[{"delta":{}}]}
        \\
        \\
    ;

    const event = try parser.parseChunk(sse_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expect(!evt.is_done);
        try testing.expect(evt.content == null or evt.content.?.len == 0);
    }
}

test "handle mixed partial chunks" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    // Simulate network chunks arriving in pieces
    const chunks = [_][]const u8{
        "data: {\"cho",
        "ices\":[{\"delta\":{\"co",
        "ntent\":\"Test\"}}]}\n\n",
    };

    var final_event: ?streaming.StreamEvent = null;
    for (chunks) |chunk| {
        if (try parser.parseChunk(chunk)) |evt| {
            final_event = evt;
            break;
        }
    }

    try testing.expect(final_event != null);
    if (final_event) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings("Test", evt.content.?);
    }
}

test "ignore event: lines" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const sse_data =
        \\event: message_start
        \\data: {"choices":[{"delta":{"content":"Content"}}]}
        \\
        \\
    ;

    const event = try parser.parseChunk(sse_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings("Content", evt.content.?);
    }
}

test "handle malformed JSON gracefully" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const malformed_data =
        \\data: {broken json here}
        \\
        \\
    ;

    // Should not crash, might return null or empty content
    const event = parser.parseChunk(malformed_data) catch |err| {
        // Error is acceptable for malformed data
        try testing.expect(err == error.UnexpectedToken or err == error.SyntaxError);
        return;
    };

    // If it returns an event, content should be null or empty
    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expect(evt.content == null or evt.content.?.len == 0);
    }
}

test "parse OpenAI streaming format" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const openai_data =
        \\data: {"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"OpenAI"},"finish_reason":null}]}
        \\
        \\
    ;

    const event = try parser.parseChunk(openai_data);
    try testing.expect(event != null);

    if (event) |evt| {
        defer evt.deinit(allocator);
        try testing.expectEqualStrings("OpenAI", evt.content.?);
    }
}

test "multiple events in one chunk" {
    const allocator = testing.allocator;

    var parser = streaming.SSEParser.init(allocator);
    defer parser.deinit();

    const multi_event_data =
        \\data: {"choices":[{"delta":{"content":"First"}}]}
        \\
        \\data: {"choices":[{"delta":{"content":"Second"}}]}
        \\
        \\
    ;

    // Parser should return first event
    const event1 = try parser.parseChunk(multi_event_data);
    try testing.expect(event1 != null);

    if (event1) |evt| {
        defer evt.deinit(allocator);
        // Should get "First" (the parser returns the first complete event it finds)
        try testing.expect(evt.content != null);
    }
}
