const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("seiargs", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("root.zig"),
    });

    const tests = b.addTest(.{
        .root_module = lib,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the tests");
    test_step.dependOn(&run_tests.step);

    const docs_obj = b.addObject(.{
        .name = "seiargs-docs",
        .root_module = lib,
    });
    const docs = docs_obj.getEmittedDocs();

    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Build and install the docs");
    docs_step.dependOn(&docs_install.step);

    const port = b.option([]const u8, "port", "Port used to serve docs") orelse ":8080";

    const serve_docs = b.addSystemCommand(&.{ "caddy", "file-server", "--root" });
    serve_docs.addDirectoryArg2(docs, .{});
    serve_docs.addArgs(&.{ "--listen", port });

    const serve_docs_step = b.step("serve-docs", "Serve docs with caddy");
    serve_docs_step.dependOn(&serve_docs.step);
}
