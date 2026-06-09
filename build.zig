const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse false;

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const exe = b.addExecutable(.{
        .name = "notch-detection",
        .root_module = exe_mod,
    });

    const dvui_dep = b.dependency("dvui", .{ .target = target, .optimize = optimize, .backend = .sdl3 });

    exe.root_module.addImport("dvui", dvui_dep.module("dvui_sdl3"));
    // exe.root_module.addImport("sdl-backend", dvui_dep.module("sdl3"));
    //

    exe.root_module.addAnonymousImport("license", .{
        .root_source_file = b.path("LICENSE"),
    });
    exe.root_module.addAnonymousImport("teaminfo", .{
        .root_source_file = b.path("TEAMINFO"),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
