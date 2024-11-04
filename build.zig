const std = @import("std");
const rayc = @import("raylib-c/src/build2.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // create a viewer to compare the output relative to what is desired
    // or just to inspect it or part of it
    {
        const options = rayc.Options{};
        const raylib = rayc.addRaylib(b, target, .ReleaseFast, options);
        raylib.root_module.addCMacro("SUPPORT_FILEFORMAT_PNM", "1");
        b.installArtifact(raylib);
        const viewer = b.addExecutable(.{
            .name = "viewer",
            .root_source_file = b.path("tool/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        viewer.addIncludePath(b.path("raylib-c/src"));
        viewer.linkLibrary(raylib);
        const install_viewer = b.addInstallArtifact(viewer, .{});

        const run_cmd = b.addRunArtifact(viewer);
        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.step.dependOn(&install_viewer.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("view", "start a gui to view the raytracing");
        run_step.dependOn(&run_cmd.step);
    }
    // convert ppm image to png
    {
        // part of image magic package on debian
        const convert_ppm = b.addSystemCommand(&.{"convert"});
        // convert image.ppm image.png
        const input_file = if (b.args) |args| args[0] else "image.ppm";

        convert_ppm.addArgs(&.{
            input_file,
            "image.png",
        });
        convert_ppm.addFileInput(b.path("image.ppm"));
        convert_ppm.addFileInput(b.path("image.png"));
        const run_step = b.step("convert", "convert image.ppm into image.png to add into markdown");
        run_step.dependOn(&convert_ppm.step);
    }
    const exe = b.addExecutable(.{
        .name = "raytracing",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
