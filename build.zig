const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get libvaxis dependency
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zcode",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Tests
    const test_step = b.step("test", "Run unit tests");

    // Parser module
    const parser_mod = b.createModule(.{
        .root_source_file = b.path("src/parser.zig"),
        .target = target,
    });

    // Parser tests
    const parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/parser_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "parser", .module = parser_mod },
            },
        }),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);

    // Tool modules
    const read_file_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/read_file.zig"),
        .target = target,
    });
    const list_files_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/list_files.zig"),
        .target = target,
    });
    const edit_file_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/edit_file.zig"),
        .target = target,
    });

    // Tools tests
    const tools_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/tools_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "read_file", .module = read_file_mod },
                .{ .name = "list_files", .module = list_files_mod },
                .{ .name = "edit_file", .module = edit_file_mod },
            },
        }),
    });
    const run_tools_tests = b.addRunArtifact(tools_tests);
    test_step.dependOn(&run_tools_tests.step);

    // Streaming module
    const streaming_mod = b.createModule(.{
        .root_source_file = b.path("src/api/streaming.zig"),
        .target = target,
    });

    // Streaming tests
    const streaming_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/streaming_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "streaming", .module = streaming_mod },
            },
        }),
    });
    const run_streaming_tests = b.addRunArtifact(streaming_tests);
    test_step.dependOn(&run_streaming_tests.step);

    // Syntax module
    const syntax_mod = b.createModule(.{
        .root_source_file = b.path("src/ui/syntax.zig"),
        .target = target,
    });

    // Syntax tests
    const syntax_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/syntax_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "syntax", .module = syntax_mod },
            },
        }),
    });
    const run_syntax_tests = b.addRunArtifact(syntax_tests);
    test_step.dependOn(&run_syntax_tests.step);
}
