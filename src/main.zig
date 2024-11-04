const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const color = @import("color.zig");
const Vec = @import("vec3.zig").Vec;
const Point = @import("vec3.zig").Point;
const Ray = @import("ray.zig").Ray;
const hittable = @import("hittable.zig");
const Camera = @import("camera.zig");
const materials = @import("material.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    // defer {
    //     _ = gpa.deinit();
    // }
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.args();
    var bar: bool = true;
    var samples: u8 = 100;
    var depth: u8 = 50;
    var png = false;
    var path: []const u8 = undefined;

    var rectangle: [4]i32 = .{ 0, 0, std.math.maxInt(i32), std.math.maxInt(i32) };
    while (args.next()) |argument| {
        if (std.mem.startsWith(u8, argument, "--help")) {
            std.debug.print("سليم يسطع على الكرات\n", .{});
            std.debug.print("\t--help  to display help\n", .{});
            std.debug.print("\t--nobar to disable the progress bar\n", .{});
            std.debug.print("\t--samples <number>\n", .{});
            std.debug.print("\t--depth <number>\n", .{});
            std.debug.print("\t--png <filename>\n", .{});
            std.debug.print("\t--rect <top left x> <top left y> <bottom right x> bottom right y>\n", .{});
            return;
        } else if (std.mem.startsWith(u8, argument, "--nobar")) {
            bar = false;
        } else if (std.mem.startsWith(u8, argument, "--samples")) {
            if (args.next()) |value_str| {
                samples = try std.fmt.parseInt(u8, value_str, 10);
            } else {
                std.debug.print("--samples <value>\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, argument, "--depth")) {
            if (args.next()) |value_str| {
                depth = try std.fmt.parseInt(u8, value_str, 10);
            } else {
                std.debug.print("--depth <value>\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, argument, "--png")) {
            if (args.next()) |image_path| {
                path = try g_allocator.dupe(u8, image_path);
                png = true;
            }
        } else if (std.mem.startsWith(u8, argument, "--rect")) {
            if (args.next()) |dims| {
                var it = std.mem.splitSequence(u8, dims, " ");
                for (0..4) |i| {
                    const dim = it.next() orelse return;
                    rectangle[i] = @intFromFloat(try std.fmt.parseFloat(f32, dim));
                }
            } else {
                std.debug.print("--rect <tlx> <tly> <brx> <bry>\n", .{});
                return;
            }
        }
    }
    var camera = Camera.init();
    camera.max_depth = depth;
    camera.samples_per_pixel = samples;
    camera.vfov = 90;
    rectangle[0] = @max(0, rectangle[0]);
    rectangle[1] = @max(0, rectangle[1]);
    rectangle[2] = @min(camera.image_width, rectangle[2]);
    rectangle[3] = @min(camera.image_height, rectangle[3]);

    // try rayTracing(allocator, bar);
    // try rayTracingCamera(allocator, camera, rectangle, bar, png, path);
    try rayTracingFOV(allocator, camera, rectangle, bar);
}
pub fn rayTracingFOV(arena: std.mem.Allocator, camera: Camera, rectangle: [4]i32, bar: bool) !void {
    var prng = std.Random.DefaultPrng.init(t: {
        const seed: u64 = @intCast((std.time.timestamp()));
        break :t seed;
    });
    const random = prng.random();

    const R = @cos(std.math.pi / 4.0);
    var material_left = materials.Lambertian.init(
        random,
        color.Rgb.init(0, 0, 1),
    );
    var material_right = materials.Lambertian.init(
        random,
        color.Rgb.init(1, 0, 0),
    );
    var world: hittable.Set = .{
        .sphere = std.ArrayList(hittable.Sphere).init(arena),
    };
    try world.sphere.append(.{
        .center = Point.init(-R, 0, -1),
        .radius = R,
        .material = material_left.material(),
    });
    try world.sphere.append(.{
        .center = Point.init(R, 0, -1),
        .radius = R,
        .material = material_right.material(),
    });
    const stdout = std.io.getStdOut().writer();
    var buffered_stdout = std.io.bufferedWriter(stdout);
    const writer = buffered_stdout.writer();

    try camera.render(writer, random, world, rectangle, bar);
    try buffered_stdout.flush();
}
pub fn rayTracingCamera(arena: std.mem.Allocator, camera: Camera, rectangle: [4]i32, bar: bool, png: bool, path: []const u8) !void {
    var prng = std.Random.DefaultPrng.init(t: {
        const seed: u64 = @intCast((std.time.timestamp()));
        break :t seed;
    });
    const random = prng.random();

    var material_ground = materials.Lambertian.init(
        random,
        color.Rgb.init(0.8, 0.8, 0),
    );
    var material_center = materials.Lambertian.init(
        random,
        color.Rgb.init(0.1, 0.2, 0.5),
    );
    // var material_left = materials.Metal.init(
    //     random,
    //     color.Rgb.init(0.8, 0.8, 0.8),
    //     0.3,
    // );
    // refraction index of glass is 1.5
    var material_left = materials.Dielectric.init(random, 1.5);
    var material_bubble = materials.Dielectric.init(random, 1.0 / 1.5);
    var material_right = materials.Metal.init(
        random,
        color.Rgb.init(0.8, 0.6, 0.2),
        1.0,
    );

    var world: hittable.Set = .{
        .sphere = std.ArrayList(hittable.Sphere).init(arena),
    };
    try world.sphere.append(.{
        .center = Point.init(0, -100.5, -1),
        .radius = 100,
        .material = material_ground.material(),
    });
    try world.sphere.append(.{
        .center = Point.init(0, 0, -1.2),
        .radius = 0.5,
        .material = material_center.material(),
    });
    try world.sphere.append(.{
        .center = Point.init(-1, 0, -1),
        .radius = 0.5,
        .material = material_left.material(),
    });
    try world.sphere.append(.{
        .center = Point.init(-1, 0, -1),
        .radius = 0.4,
        .material = material_bubble.material(),
    });
    try world.sphere.append(.{
        .center = Point.init(1, 0, -1),
        .radius = 0.5,
        .material = material_right.material(),
    });
    // Render
    if (!png) {
        const stdout = std.io.getStdOut().writer();
        var buffered_stdout = std.io.bufferedWriter(stdout);
        const writer = buffered_stdout.writer();

        try camera.render(writer, random, world, rectangle, bar);
        try buffered_stdout.flush();
    } else {
        // const png_file_name = try std.fmt.allocPrint(arena, "{s}.png", .{path});
        const ppm_file_name = try std.fmt.allocPrint(arena, "{s}.ppm", .{path});
        const ppm_file = try std.fs.cwd().createFile(ppm_file_name, .{});
        defer ppm_file.close();
        var buffered_writer = std.io.bufferedWriter(ppm_file.writer());
        const writer = buffered_writer.writer();

        try camera.render(writer, random, world, rectangle, bar);
        try buffered_writer.flush();

        var convert_process = std.process.Child.init(&.{ "convert", ppm_file_name, path }, arena);
        try convert_process.spawn();
        _ = try convert_process.wait();
    }
}
