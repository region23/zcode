const std = @import("std");
const config = @import("config.zig");
const api_common = @import("api/common.zig");
const api_client = @import("api/client.zig");
const api_openai = @import("api/openai.zig");
const tools = @import("tools/registry.zig");
const read_file = @import("tools/read_file.zig");
const list_files = @import("tools/list_files.zig");
const edit_file = @import("tools/edit_file.zig");

pub const AppState = struct {
    conversation: api_common.Conversation,
    tool_registry: tools.ToolRegistry,
    api_client: api_client.ApiClient,
    current_provider: config.ApiProvider,
    current_model: []const u8,
    current_mode: config.Mode,
    input_buffer: std.ArrayList(u8),
    scroll_offset: usize,
    is_streaming: bool,
    show_modal: bool,
    allocator: std.mem.Allocator,
    config: config.Config,

    pub fn init(allocator: std.mem.Allocator, cfg: config.Config) !AppState {
        // Create tool registry
        var registry = tools.ToolRegistry.init(allocator);
        try registry.register(read_file.getTool());
        try registry.register(list_files.getTool());
        try registry.register(edit_file.getTool());

        // Get default provider and model
        const provider = cfg.default_provider;
        const model = config.getDefaultModel(provider);

        // Get API key for default provider
        const api_key = cfg.getApiKey(provider) orelse {
            std.debug.print("No API key found for provider {s}\n", .{@tagName(provider)});
            return error.NoApiKey;
        };

        // Create API client (only OpenAI for Phase 1)
        const client = switch (provider) {
            .openai => blk: {
                const openai_client = try api_openai.OpenAIClient.init(
                    allocator,
                    api_key,
                    model,
                    cfg.max_tokens,
                );
                break :blk openai_client.asApiClient();
            },
            else => {
                std.debug.print("Provider {s} not yet implemented (Phase 2)\n", .{@tagName(provider)});
                return error.ProviderNotImplemented;
            },
        };

        var state = AppState{
            .conversation = api_common.Conversation.init(allocator),
            .tool_registry = registry,
            .api_client = client,
            .current_provider = provider,
            .current_model = try allocator.dupe(u8, model),
            .current_mode = cfg.default_mode,
            .input_buffer = std.ArrayList(u8).init(allocator),
            .scroll_offset = 0,
            .is_streaming = false,
            .show_modal = false,
            .allocator = allocator,
            .config = cfg,
        };

        // Add system prompt
        const system_prompt = try state.tool_registry.generateSystemPrompt(state.current_mode, allocator);
        defer allocator.free(system_prompt);

        try state.conversation.append(.system, system_prompt);

        return state;
    }

    pub fn deinit(self: *AppState) void {
        self.conversation.deinit();
        self.tool_registry.deinit();
        self.api_client.deinit();
        self.allocator.free(self.current_model);
        self.input_buffer.deinit();
        self.config.deinit();
    }

    /// Toggle between plan and build modes
    pub fn toggleMode(self: *AppState) !void {
        self.current_mode = switch (self.current_mode) {
            .plan => .build,
            .build => .plan,
        };

        // Regenerate system prompt with new mode
        const system_prompt = try self.tool_registry.generateSystemPrompt(self.current_mode, self.allocator);
        defer self.allocator.free(system_prompt);

        // Replace system message (first message should be system)
        if (self.conversation.messages.items.len > 0) {
            var first_msg = &self.conversation.messages.items[0];
            if (first_msg.role == .system) {
                self.allocator.free(first_msg.content);
                first_msg.content = try self.allocator.dupe(u8, system_prompt);
            }
        }
    }

    /// Clear the conversation (keep system prompt)
    pub fn clearConversation(self: *AppState) void {
        // Save system prompt
        const system_msg = if (self.conversation.messages.items.len > 0 and
            self.conversation.messages.items[0].role == .system)
            self.conversation.messages.items[0]
        else
            null;

        // Clear all messages
        self.conversation.clear();

        // Re-add system prompt if it existed
        if (system_msg) |msg| {
            self.conversation.append(.system, msg.content) catch {};
        }
    }

    /// Submit the current input buffer as a user message
    pub fn submitInput(self: *AppState) !void {
        if (self.input_buffer.items.len == 0) return;

        const input = try self.allocator.dupe(u8, self.input_buffer.items);
        defer self.allocator.free(input);

        try self.conversation.append(.user, input);
        self.input_buffer.clearRetainingCapacity();
    }

    /// Get the mode indicator string for display
    pub fn getModeString(self: *const AppState) []const u8 {
        return switch (self.current_mode) {
            .plan => "[PLAN]",
            .build => "[BUILD]",
        };
    }
};
