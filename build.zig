const std = @import("std");
const filename = "p1xel_editor";
const filename_win = "p1xel_editor.exe";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{
        .name = filename,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const raylib_artifact = raylib_dep.artifact("raylib");
    exe.linkLibrary(raylib_artifact);

    const raylib = raylib_dep.module("raylib");
    exe.root_module.addImport("raylib", raylib);

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
