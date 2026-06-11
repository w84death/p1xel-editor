const std = @import("std");
const filename = "p1xel-editor";

const Edition = enum { shareware, full };

fn configureLinks(exe: *std.Build.Step.Compile, os_tag: std.Target.Os.Tag) void {
    switch (os_tag) {
        .windows => {
            exe.root_module.linkSystemLibrary("gdi32", .{});
            exe.root_module.linkSystemLibrary("winmm", .{});
        },
        .linux => {
            exe.root_module.linkSystemLibrary("X11", .{});
            exe.root_module.linkSystemLibrary("asound", .{});
        },
        else => {},
    }
}

fn addBuildOptions(b: *std.Build, module: *std.Build.Module, edition: Edition) void {
    const options = b.addOptions();
    options.addOption(bool, "full_version", edition == .full);
    module.addOptions("build_options", options);
}

fn addAppExe(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    edition: Edition,
) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    addBuildOptions(b, exe.root_module, edition);
    exe.root_module.addIncludePath(b.path("src/libs"));
    exe.root_module.addCSourceFile(.{ .file = b.path("src/libs/fenster.c"), .flags = &[_][]const u8{} });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/libs/fenster_audio.c"), .flags = &[_][]const u8{} });
    configureLinks(exe, target.result.os.tag);
    exe.root_module.linkSystemLibrary("c", .{});

    return exe;
}

fn addReleaseExe(
    b: *std.Build,
    step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    target_suffix: []const u8,
    edition: Edition,
) void {
    const release_name = b.fmt("{s}-{s}-{s}", .{ filename, @tagName(edition), target_suffix });
    const release_exe = addAppExe(b, release_name, target, .ReleaseFast, edition);
    const release_install = b.addInstallArtifact(release_exe, .{});

    const release_binary_name = b.fmt("{s}{s}", .{
        release_name,
        if (target.result.os.tag == .windows) ".exe" else "",
    });
    const release_install_path = b.getInstallPath(.bin, release_binary_name);
    const release_upx = b.addSystemCommand(&[_][]const u8{
        "upx",
        "--best",
        "--lzma",
        "--compress-icons=0",
        release_install_path,
    });

    release_upx.step.dependOn(&release_install.step);
    step.dependOn(&release_upx.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const selected_edition = b.option(Edition, "edition", "Build edition: shareware or full") orelse .shareware;

    const exe = addAppExe(b, filename, target, optimize, selected_edition);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/editor_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    addBuildOptions(b, test_module, selected_edition);
    const unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const release_linux_step = b.step("release-linux", "Build Linux host target for shareware and full editions (ReleaseFast + UPX)");
    const host_target = target;

    const release_windows_step = b.step("release-windows", "Build Windows 32/64 for shareware and full editions (ReleaseFast + UPX)");
    const windows_matrix = [_]struct {
        arch: std.Target.Cpu.Arch,
        os: std.Target.Os.Tag,
        suffix: []const u8,
    }{
        .{ .arch = .x86, .os = .windows, .suffix = "windows-x86" },
        .{ .arch = .x86_64, .os = .windows, .suffix = "windows-x86_64" },
    };
    const release_editions = [_]Edition{ .shareware, .full };

    if (host_target.result.os.tag == .linux) {
        const host_suffix = switch (host_target.result.cpu.arch) {
            .x86 => "linux-x86",
            .x86_64 => "linux-x86_64",
            else => "linux",
        };

        inline for (release_editions) |edition| {
            addReleaseExe(b, release_linux_step, host_target, host_suffix, edition);
        }
    }

    inline for (windows_matrix) |entry| {
        const matrix_target = b.resolveTargetQuery(.{
            .cpu_arch = entry.arch,
            .os_tag = entry.os,
        });

        inline for (release_editions) |edition| {
            addReleaseExe(b, release_windows_step, matrix_target, entry.suffix, edition);
        }
    }
}
