const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zcode",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add libvaxis dependency
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vaxis", vaxis.module("vaxis"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const test_step = b.step("test", "Run unit tests");

    // Parser tests
    const parser_tests = b.addTest(.{
        .root_source_file = b.path("test/parser_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    parser_tests.root_module.addAnonymousImport("parser", .{
        .root_source_file = b.path("src/parser.zig"),
    });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    test_step.dependOn(&run_parser_tests.step);

    // Tools tests
    const tools_tests = b.addTest(.{
        .root_source_file = b.path("test/tools_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tools_tests.root_module.addAnonymousImport("read_file", .{
        .root_source_file = b.path("src/tools/read_file.zig"),
    });
    tools_tests.root_module.addAnonymousImport("list_files", .{
        .root_source_file = b.path("src/tools/list_files.zig"),
    });
    tools_tests.root_module.addAnonymousImport("edit_file", .{
        .root_source_file = b.path("src/tools/edit_file.zig"),
    });
    const run_tools_tests = b.addRunArtifact(tools_tests);
    test_step.dependOn(&run_tools_tests.step);

    // Streaming tests
    const streaming_tests = b.addTest(.{
        .root_source_file = b.path("test/streaming_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    streaming_tests.root_module.addAnonymousImport("streaming", .{
        .root_source_file = b.path("src/api/streaming.zig"),
    });
    const run_streaming_tests = b.addRunArtifact(streaming_tests);
    test_step.dependOn(&run_streaming_tests.step);

    // Syntax tests
    const syntax_tests = b.addTest(.{
        .root_source_file = b.path("test/syntax_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    syntax_tests.root_module.addAnonymousImport("syntax", .{
        .root_source_file = b.path("src/ui/syntax.zig"),
    });
    const run_syntax_tests = b.addRunArtifact(syntax_tests);
    test_step.dependOn(&run_syntax_tests.step);
}
