const std = @import("std");

const ROM_PATH = "ROM/p1x_gbc_engine.gbc";
const OBJ_PATH = "BUILD/main.o";

pub fn build(b: *std.Build) void {
    const project_root = b.path(".");

    const prepare_dirs = b.addSystemCommand(&[_][]const u8{
        "mkdir",
        "-p",
        "BUILD",
        "ROM",
    });
    prepare_dirs.setCwd(project_root);

    const assemble = b.addSystemCommand(&[_][]const u8{
        "rgbasm",
        "-o",
        OBJ_PATH,
        "SRC/main.asm",
    });
    assemble.setCwd(project_root);
    assemble.step.dependOn(&prepare_dirs.step);

    const link = b.addSystemCommand(&[_][]const u8{
        "rgblink",
        "-o",
        ROM_PATH,
        "-m",
        "ROM/p1x_gbc_engine.map",
        "-n",
        "ROM/p1x_gbc_engine.sym",
        OBJ_PATH,
    });
    link.setCwd(project_root);
    link.step.dependOn(&assemble.step);

    const fix = b.addSystemCommand(&[_][]const u8{
        "rgbfix",
        "-v",
        "-p",
        "0",
        "-C",
        "-t",
        "P1X GBC ENGINE",
        ROM_PATH,
    });
    fix.setCwd(project_root);
    fix.step.dependOn(&link.step);

    const build_rom = b.step("build", "Build the GBC ROM");
    build_rom.dependOn(&fix.step);
    b.default_step.dependOn(&fix.step);

    const run = b.addSystemCommand(&[_][]const u8{
        "mgba",
        ROM_PATH,
    });
    run.setCwd(project_root);
    run.step.dependOn(&fix.step);

    const emulate = b.step("emulate", "Build and run in mGBA");
    emulate.dependOn(&run.step);
}
