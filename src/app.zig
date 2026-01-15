const std = @import("std");
const config = @import("config.zig");
const api_common = @import("api/common.zig");
const api_client = @import("api/client.zig");
const api_openai = @import("api/openai.zig");
const api_anthropic = @import("api/anthropic.zig");
const api_zai = @import("api/zai.zig");
const api_openrouter = @import("api/openrouter.zig");
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
    input_buffer: std.array_list.AlignedManaged(u8, null),
    scroll_offset: usize,
    is_streaming: bool,
    show_modal: bool,
    modal_cursor: usize,
    modal_expanded_provider: ?config.ApiProvider,
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

        // Create API client for all providers
        const client = try createApiClient(provider, api_key, model, cfg.max_tokens, allocator);

        var state = AppState{
            .conversation = api_common.Conversation.init(allocator),
            .tool_registry = registry,
            .api_client = client,
            .current_provider = provider,
            .current_model = try allocator.dupe(u8, model),
            .current_mode = cfg.default_mode,
            .input_buffer = std.array_list.AlignedManaged(u8, null).init(allocator),
            .scroll_offset = 0,
            .is_streaming = false,
            .show_modal = false,
            .modal_cursor = 0,
            .modal_expanded_provider = null,
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

    /// Open the provider/model selection modal
    pub fn openModal(self: *AppState) void {
        self.show_modal = true;
        self.modal_cursor = 0;
        self.modal_expanded_provider = self.current_provider;
    }

    /// Close the modal without changes
    pub fn closeModal(self: *AppState) void {
        self.show_modal = false;
        self.modal_cursor = 0;
        self.modal_expanded_provider = null;
    }

    /// Switch to a new provider and model
    pub fn switchProviderAndModel(self: *AppState, provider: config.ApiProvider, model: []const u8) !void {
        // Get API key for new provider
        const api_key = self.config.getApiKey(provider) orelse {
            return error.NoApiKey;
        };

        // Clean up old API client and model string
        self.api_client.deinit();
        self.allocator.free(self.current_model);

        // Create new API client
        const new_client = try createApiClient(provider, api_key, model, self.config.max_tokens, self.allocator);

        // Update state
        self.api_client = new_client;
        self.current_provider = provider;
        self.current_model = try self.allocator.dupe(u8, model);

        // Close modal
        self.closeModal();
    }
};

/// Create an API client for the given provider
fn createApiClient(
    provider: config.ApiProvider,
    api_key: []const u8,
    model: []const u8,
    max_tokens: usize,
    allocator: std.mem.Allocator,
) !api_client.ApiClient {
    return switch (provider) {
        .openai => blk: {
            const openai_client = try api_openai.OpenAIClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk openai_client.asApiClient();
        },
        .anthropic => blk: {
            const anthropic_client = try api_anthropic.AnthropicClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk anthropic_client.asApiClient();
        },
        .zai => blk: {
            const zai_client = try api_zai.ZAIClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk zai_client.asApiClient();
        },
        .deepseek => blk: {
            // DeepSeek via OpenRouter
            const or_client = try api_openrouter.OpenRouterClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk or_client.asApiClient();
        },
        .qwen => blk: {
            // Qwen via OpenRouter
            const or_client = try api_openrouter.OpenRouterClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk or_client.asApiClient();
        },
        .openrouter => blk: {
            const or_client = try api_openrouter.OpenRouterClient.init(
                allocator,
                api_key,
                model,
                max_tokens,
            );
            break :blk or_client.asApiClient();
        },
    };
}
