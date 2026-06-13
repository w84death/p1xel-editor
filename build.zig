const std = @import("std");
const filename = "p1xel-editor";

const Edition = enum { shareware, full };

const appimage_arch = "x86_64";
const appimagetool_names = [_][]const u8{ "appimagetool", "appimagetool-x86_64.AppImage", "appimagetool.AppImage" };
const appimagetool_search_paths = [_][]const u8{ ".", ".zig-cache", "zig-out/bin" };

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

fn addAppImage(
    b: *std.Build,
    step: *std.Build.Step,
    appimagetool_path: []const u8,
    target: std.Build.ResolvedTarget,
    edition: Edition,
) void {
    const release_name = b.fmt("{s}-{s}-linux-{s}-glibc-bundled", .{ filename, @tagName(edition), appimage_arch });
    const release_exe = addAppExe(b, release_name, target, .ReleaseFast, edition);
    addLinuxHostLibraryPaths(release_exe);

    const appdir = b.addTempFiles();
    const appdir_path = appdir.getDirectory();
    _ = appdir.addCopyFile(release_exe.getEmittedBin(), b.fmt("usr/bin/{s}", .{filename}));
    _ = appdir.add("AppRun", appimageAppRun());
    _ = appdir.add(b.fmt("{s}.desktop", .{filename}), appimageDesktopFile());
    _ = appdir.addCopyFile(b.path("docs/logo.png"), ".DirIcon");
    _ = appdir.addCopyFile(b.path("docs/logo.png"), b.fmt("{s}.png", .{filename}));
    _ = appdir.addCopyFile(b.path("docs/logo.png"), b.fmt("usr/share/icons/hicolor/256x256/apps/{s}.png", .{filename}));

    const prepare_appdir = b.addSystemCommand(&[_][]const u8{ "sh", "-eu", "-c", appimagePrepareScript(), "prepare-appdir" });
    prepare_appdir.addDirectoryArg(appdir_path);

    const appimage_name = b.fmt("{s}.AppImage", .{release_name});
    const appimagetool = b.addSystemCommand(&[_][]const u8{appimagetool_path});
    appimagetool.stdio = .inherit;
    appimagetool.setEnvironmentVariable("ARCH", appimage_arch);
    appimagetool.addDirectoryArg(appdir_path);
    const appimage_file = appimagetool.addOutputFileArg(appimage_name);
    appimagetool.step.dependOn(&prepare_appdir.step);

    const install_appimage = b.addInstallBinFile(appimage_file, appimage_name);
    step.dependOn(&install_appimage.step);
}

fn addLinuxHostLibraryPaths(exe: *std.Build.Step.Compile) void {
    const include_paths = [_][]const u8{
        "/usr/include",
        "/usr/local/include",
        "/usr/include/x86_64-linux-gnu",
    };
    const library_paths = [_][]const u8{
        "/usr/lib",
        "/usr/lib64",
        "/lib",
        "/lib64",
        "/usr/lib/x86_64-linux-gnu",
        "/lib/x86_64-linux-gnu",
    };
    inline for (include_paths) |path| if (pathExists(path)) exe.root_module.addSystemIncludePath(.{ .cwd_relative = path });
    inline for (library_paths) |path| if (pathExists(path)) exe.root_module.addLibraryPath(.{ .cwd_relative = path });
}

fn pathExists(path: []const u8) bool {
    std.Io.Dir.accessAbsolute(std.Options.debug_io, path, .{}) catch return false;
    return true;
}

fn appimageAppRun() []const u8 {
    return
    \\#!/bin/sh
    \\set -eu
    \\SELF="$0"
    \\case "$SELF" in
    \\    */*) ;;
    \\    *) SELF="$(command -v -- "$SELF")" ;;
    \\esac
    \\HERE="$(dirname "$(readlink -f "$SELF")")"
    \\LIBDIR="$HERE/usr/lib"
    \\LOADER="$LIBDIR/ld-linux-x86-64.so.2"
    \\LIBPATH="$LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    \\if [ -x "$LOADER" ]; then
    \\    exec "$LOADER" --library-path "$LIBPATH" "$HERE/usr/bin/p1xel-editor" "$@"
    \\fi
    \\export LD_LIBRARY_PATH="$LIBPATH"
    \\exec "$HERE/usr/bin/p1xel-editor" "$@"
    \\
    ;
}

fn appimageDesktopFile() []const u8 {
    return
    \\[Desktop Entry]
    \\Type=Application
    \\Name=P1Xel Editor
    \\Exec=p1xel-editor
    \\Icon=p1xel-editor
    \\Categories=Graphics;2DGraphics;RasterGraphics;
    \\Terminal=false
    \\
    ;
}

fn appimageToolMissingMessage() []const u8 {
    return
    \\release-appimage requires AppImageKit appimagetool, the AppImage packaging tool.
    \\
    \\appimage-cli-tool is a store/install/update CLI and cannot create AppImages.
    \\
    \\Install appimagetool in PATH, or pass an explicit path:
    \\  zig build release-appimage -Dappimagetool=/path/to/appimagetool
    \\
    \\Example local download:
    \\  wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    \\  chmod +x appimagetool
    \\  zig build release-appimage -Dappimagetool=./appimagetool
    ;
}

fn appimagePrepareScript() []const u8 {
    return
    \\appdir="$1"
    \\exe="$appdir/usr/bin/p1xel-editor"
    \\libdir="$appdir/usr/lib"
    \\mkdir -p "$libdir"
    \\chmod +x "$appdir/AppRun" "$exe"
    \\ldd "$exe" | while IFS= read -r line; do
    \\    set -- $line
    \\    case "$line" in
    \\        *"=>"*"/"*) lib="$3" ;;
    \\        /*) lib="$1" ;;
    \\        *) continue ;;
    \\    esac
    \\    case "$lib" in
    \\        /*) cp -L "$lib" "$libdir/$(basename "$lib")" ;;
    \\    esac
    \\done
    \\for loader in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /usr/lib64/ld-linux-x86-64.so.2 /usr/lib/ld-linux-x86-64.so.2; do
    \\    if [ -e "$loader" ]; then
    \\        cp -L "$loader" "$libdir/ld-linux-x86-64.so.2"
    \\        chmod +x "$libdir/ld-linux-x86-64.so.2"
    \\        break
    \\    fi
    \\done
    \\if [ ! -x "$libdir/ld-linux-x86-64.so.2" ]; then
    \\    echo "missing bundled x86_64 glibc loader" >&2
    \\    exit 1
    \\fi
    \\
    ;
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
    const release_appimage_step = b.step("release-appimage", "Build x86_64 AppImages with bundled glibc/libs for shareware and full editions");
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

    if (host_target.result.os.tag == .linux and host_target.result.cpu.arch == .x86_64) {
        const appimagetool_path: ?[]const u8 = b.option([]const u8, "appimagetool", "Path to AppImageKit appimagetool executable") orelse (b.findProgram(&appimagetool_names, &appimagetool_search_paths) catch null);
        if (appimagetool_path) |tool_path| {
            inline for (release_editions) |edition| {
                addAppImage(b, release_appimage_step, tool_path, host_target, edition);
            }
        } else {
            release_appimage_step.dependOn(&b.addFail(appimageToolMissingMessage()).step);
        }
    } else {
        release_appimage_step.dependOn(&b.addFail("release-appimage requires a Linux x86_64 host").step);
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
