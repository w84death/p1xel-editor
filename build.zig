const std = @import("std");
const filename = "p1xel_editor";
const filename_win = "p1xel_editor.exe";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = filename,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addIncludePath(b.path("src"));

    exe.addCSourceFile(.{ .file = b.path("src/fenster.c"), .flags = &[_][]const u8{} });
    switch (target.result.os.tag) {
        .macos => exe.linkFramework("Cocoa"),
        .windows => exe.linkSystemLibrary("gdi32"),
        .linux => exe.linkSystemLibrary("X11"),
        else => {},
    }

    exe.linkLibC();

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const upx_step = b.step("upx", "Compress binary");
    const binary_name = if (target.result.os.tag == .windows)
        filename_win
    else
        filename;
    const install_path = b.getInstallPath(.bin, binary_name);
    const compress = b.addSystemCommand(&[_][]const u8{
        "upx",
        "--best",
        "--lzma",
        "--compress-icons=0",
        install_path,
    });
    compress.step.dependOn(b.getInstallStep());
    upx_step.dependOn(&compress.step);
}
