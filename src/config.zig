const std = @import("std");

pub const ApiProvider = enum {
    openai,
    anthropic,
    zai,
    deepseek,
    qwen,
    openrouter,
};

pub const Mode = enum {
    plan,
    build,
};

pub const ModelConfig = struct {
    default: []const u8,
    available: []const []const u8,
};

pub const Config = struct {
    // API Keys
    openai_key: ?[]const u8 = null,
    anthropic_key: ?[]const u8 = null,
    zai_key: ?[]const u8 = null,
    deepseek_key: ?[]const u8 = null,
    qwen_key: ?[]const u8 = null,
    openrouter_key: ?[]const u8 = null,

    // Defaults
    default_provider: ApiProvider = .openai,
    default_mode: Mode = .build,
    max_tokens: usize = 2000,

    allocator: std.mem.Allocator,

    pub fn load(allocator: std.mem.Allocator) !Config {
        var config = Config{
            .allocator = allocator,
        };

        // Try to load from environment variables
        // This is a simplified version - full implementation would also check config files
        config.openai_key = std.process.getEnvVarOwned(allocator, "OPENAI_API_KEY") catch |err| blk: {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        config.anthropic_key = std.process.getEnvVarOwned(allocator, "ANTHROPIC_API_KEY") catch |err| blk: {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        config.zai_key = std.process.getEnvVarOwned(allocator, "ZAI_API_KEY") catch |err| blk: {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        config.deepseek_key = std.process.getEnvVarOwned(allocator, "DEEPSEEK_API_KEY") catch |err| blk: {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        config.qwen_key = std.process.getEnvVarOwned(allocator, "QWEN_API_KEY") catch |err| {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        config.openrouter_key = std.process.getEnvVarOwned(allocator, "OPENROUTER_API_KEY") catch |err| blk: {
            if (err != error.EnvironmentVariableNotFound) return err;
            break :blk null;
        };

        // Check for default provider override
        if (std.process.getEnvVarOwned(allocator, "ZCODE_DEFAULT_PROVIDER")) |provider_str| {
            defer allocator.free(provider_str);
            if (std.mem.eql(u8, provider_str, "openai")) {
                config.default_provider = .openai;
            } else if (std.mem.eql(u8, provider_str, "anthropic")) {
                config.default_provider = .anthropic;
            } else if (std.mem.eql(u8, provider_str, "zai")) {
                config.default_provider = .zai;
            } else if (std.mem.eql(u8, provider_str, "deepseek")) {
                config.default_provider = .deepseek;
            } else if (std.mem.eql(u8, provider_str, "qwen")) {
                config.default_provider = .qwen;
            } else if (std.mem.eql(u8, provider_str, "openrouter")) {
                config.default_provider = .openrouter;
            }
        } else |_| {}

        // Check for default mode override
        if (std.process.getEnvVarOwned(allocator, "ZCODE_DEFAULT_MODE")) |mode_str| {
            defer allocator.free(mode_str);
            if (std.mem.eql(u8, mode_str, "plan")) {
                config.default_mode = .plan;
            } else if (std.mem.eql(u8, mode_str, "build")) {
                config.default_mode = .build;
            }
        } else |_| {}

        return config;
    }

    pub fn deinit(self: *Config) void {
        if (self.openai_key) |key| self.allocator.free(key);
        if (self.anthropic_key) |key| self.allocator.free(key);
        if (self.zai_key) |key| self.allocator.free(key);
        if (self.deepseek_key) |key| self.allocator.free(key);
        if (self.qwen_key) |key| self.allocator.free(key);
        if (self.openrouter_key) |key| self.allocator.free(key);
    }

    /// Get API key for a specific provider
    pub fn getApiKey(self: *const Config, provider: ApiProvider) ?[]const u8 {
        return switch (provider) {
            .openai => self.openai_key,
            .anthropic => self.anthropic_key,
            .zai => self.zai_key,
            .deepseek => self.deepseek_key,
            .qwen => self.qwen_key,
            .openrouter => self.openrouter_key,
        };
    }

    /// Validate that at least one API key is configured
    pub fn validate(self: *const Config) !void {
        if (self.openai_key == null and
            self.anthropic_key == null and
            self.zai_key == null and
            self.deepseek_key == null and
            self.qwen_key == null and
            self.openrouter_key == null)
        {
            return error.NoApiKeyConfigured;
        }
    }
};

/// Get default model for a provider
pub fn getDefaultModel(provider: ApiProvider) []const u8 {
    return switch (provider) {
        .openai => "gpt-4o",
        .anthropic => "claude-sonnet-4-5-20250929",
        .zai => "glm-4.7",
        .deepseek => "deepseek-chat",
        .qwen => "qwen-max",
        .openrouter => "openai/gpt-4o",
    };
}

/// Get available models for a provider
pub fn getAvailableModels(provider: ApiProvider, allocator: std.mem.Allocator) ![]const []const u8 {
    _ = allocator; // For future use when we load from config file
    return switch (provider) {
        .openai => &[_][]const u8{ "gpt-4o", "gpt-4o-mini", "o1", "o1-mini" },
        .anthropic => &[_][]const u8{
            "claude-sonnet-4-5-20250929",
            "claude-opus-4-5-20251101",
            "claude-haiku-4-20250415",
        },
        .zai => &[_][]const u8{"glm-4.7"},
        .deepseek => &[_][]const u8{ "deepseek-chat", "deepseek-coder" },
        .qwen => &[_][]const u8{ "qwen-max", "qwen-plus" },
        .openrouter => &[_][]const u8{}, // User can input any model
    };
}
