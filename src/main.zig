const std = @import("std");
const assert = std.debug.assert;
const log = std.log;

const color = @import("color.zig");
const vec3 = @import("vec3.zig");
const Vec = @import("vec3.zig").Vec;
const Point = @import("vec3.zig").Point;
const Ray = @import("ray.zig").Ray;
const hittable = @import("hittable.zig");
const Camera = @import("camera.zig");
const materials = @import("material.zig");
const Lambertian = materials.Lambertian;
const Dielectric = materials.Dielectric;
const Metal = materials.Metal;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    // defer {
    //     _ = gpa.deinit();
    // }
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var camera: Camera = .{};
    camera.samples_per_pixel = 10; //100;
    camera.max_depth = 10; //50;
    camera.vfov = 20;
    camera.look_from = Point.init(-2, 2, 1);
    camera.look_at = Point.init(0, 0, -1);
    camera.view_up = Vec.init(0, 1, 0);
    camera.defocus_angle = 10;
    camera.focus_dist = 3.4;
    var args = std.process.args();
    var bar: bool = true;
    var print_state: bool = false;
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
            std.debug.print("\t--rect \"<top left x> <top left y> <bottom right x> bottom right y>\"\n", .{});
            std.debug.print("\t--vfov <n>\n", .{});
            std.debug.print("\t--defocus-angle <n>\n", .{});
            std.debug.print("\t--focus-dist <n>\n", .{});
            std.debug.print("\t--print-state\n", .{});
            return;
        } else if (std.mem.startsWith(u8, argument, "--nobar")) {
            bar = false;
        } else if (std.mem.startsWith(u8, argument, "--print-state")) {
            print_state = true;
        } else if (std.mem.startsWith(u8, argument, "--samples")) {
            if (args.next()) |value_str| {
                camera.samples_per_pixel = try std.fmt.parseInt(i32, value_str, 10);
            } else {
                std.debug.print("--samples <value>\n", .{});
                return;
            }
        } else if (std.mem.startsWith(u8, argument, "--depth")) {
            if (args.next()) |value_str| {
                camera.max_depth = try std.fmt.parseInt(u8, value_str, 10);
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
        } else if (std.mem.startsWith(u8, argument, "--vfov")) {
            if (args.next()) |v_str| {
                camera.vfov = try std.fmt.parseFloat(f32, v_str);
            }
        } else if (std.mem.startsWith(u8, argument, "--defocus-angle")) {
            if (args.next()) |a_str| {
                camera.defocus_angle = try std.fmt.parseFloat(f32, a_str);
            }
        } else if (std.mem.startsWith(u8, argument, "--focus-dist")) {
            if (args.next()) |a_str| {
                camera.focus_dist = try std.fmt.parseFloat(f32, a_str);
            }
        } else if (std.mem.startsWith(u8, argument, "--width")) {
            if (args.next()) |a_str| {
                camera.image_width = try std.fmt.parseInt(i32, a_str, 10);
            }
        } else if (std.mem.startsWith(u8, argument, "--from")) {
            for (0..3) |i| {
                if (args.next()) |s| {
                    camera.look_from.pos[i] = try std.fmt.parseFloat(f32, s);
                }
            }
        } else if (std.mem.startsWith(u8, argument, "--at")) {
            for (0..3) |i| {
                if (args.next()) |s| {
                    camera.look_at.pos[i] = try std.fmt.parseFloat(f32, s);
                }
            }
        } else if (std.mem.startsWith(u8, argument, "--up")) {
            for (0..3) |i| {
                if (args.next()) |s| {
                    camera.view_up.pos[i] = try std.fmt.parseFloat(f32, s);
                }
            }
        }
    }
    camera.init();
    if (print_state) {
        std.debug.print("camera: {any}\n", .{camera});
        return;
    }
    // try rayTracing(allocator, bar);
    // try rayTracingCamera(allocator, &camera, &rectangle, bar, png, path);
    // try rayTracingFOV(allocator, camera, rectangle, bar);
    try rayTracingCover(allocator, &camera, &rectangle, bar);
}
pub fn rayTracingCover(arena: std.mem.Allocator, camera: *Camera, rectangle: *[4]i32, bar: bool) !void {
    // camera.ideal_aspect_ratio = 16.0 / 9.0;
    // camera.image_width = 1200;
    // camera.samples_per_pixel = 500;
    // camera.max_depth = 50;
    // camera.vfov = 20;
    // camera.look_from = Point.init(13, 2, 3);
    // camera.look_at = Point.init(0, 0, 0);
    // camera.view_up = Point.init(0, 1, 0);
    // camera.defocus_angle = 0.6;
    // camera.focus_dist = 10;

    var prng = std.Random.DefaultPrng.init(t: {
        const seed: u64 = @intCast((std.time.timestamp()));
        break :t seed;
    });
    const random = prng.random();

    var world: hittable.Set = .{
        .sphere = std.ArrayList(hittable.Sphere).init(arena),
    };
    var material_ground = materials.Lambertian.init(
        random,
        color.Rgb.init(0.5, 0.5, 0.5),
    );
    try world.sphere.append(.{
        .center = Point.init(0, -1000, 0),
        .radius = 1000,
        .material = material_ground.material(),
    });
    var a: i32 = -11;
    while (a <= 11) : (a += 1) {
        var b: i32 = -11;
        while (b <= 11) : (b += 1) {
            const choose_mat = random.float(f32);
            const center = Point.init(
                @as(f32, @floatFromInt(a)) + 0.9 * random.float(f32),
                0.2,
                @as(f32, @floatFromInt(b)) + 0.9 * random.float(f32),
            );
            if (center.subImmutable(Point.init(4, 0.2, 0)).len() > 0.9) {
                if (choose_mat < 0.8) {
                    const albedo = vec3.randomVector(random, .{})
                        .mulImmutable(vec3.randomVector(random, .{}));
                    var lam = try arena.create(Lambertian);
                    lam.* = Lambertian.init(random, albedo);
                    try world.sphere.append(.{
                        .center = center,
                        .radius = 0.2,
                        .material = lam.material(),
                    });
                } else if (choose_mat < 0.95) {
                    const albedo = vec3.randomVector(random, .{ .min = 0.5, .max = 1 });
                    const fuzz = random.float(f32) * 0.5;
                    var mat = try arena.create(Metal);
                    mat.* = Metal.init(random, albedo, fuzz);
                    try world.sphere.append(.{
                        .center = center,
                        .radius = 0.2,
                        .material = mat.material(),
                    });
                } else {
                    var mat = try arena.create(Dielectric);
                    mat.* = Dielectric.init(random, 1.5);
                    try world.sphere.append(.{
                        .center = center,
                        .radius = 0.2,
                        .material = mat.material(),
                    });
                }
            }
        }
    }
    var material1 = Dielectric.init(random, 1.5);
    try world.sphere.append(.{
        .center = Point.init(0, 1, 0),
        .radius = 1,
        .material = material1.material(),
    });

    var material2 = Lambertian.init(random, color.Rgb.init(0.4, 0.2, 0.1));
    try world.sphere.append(.{
        .center = Point.init(-4, 1, 0),
        .radius = 1,
        .material = material2.material(),
    });

    var material3 = Metal.init(random, color.Rgb.init(0.7, 0.6, 0.5), 0);
    try world.sphere.append(.{
        .center = Point.init(4, 1, 0),
        .radius = 1,
        .material = material3.material(),
    });

    const stdout = std.io.getStdOut().writer();
    var buffered_stdout = std.io.bufferedWriter(stdout);
    const writer = buffered_stdout.writer();

    rectangle[0] = @max(0, rectangle[0]);
    rectangle[1] = @max(0, rectangle[1]);
    rectangle[2] = @min(camera.image_width, rectangle[2]);
    rectangle[3] = @min(camera.image_height, rectangle[3]);

    try camera.render(writer, random, world, rectangle.*, bar);
    try buffered_stdout.flush();
}
pub fn rayTracingCamera(arena: std.mem.Allocator, camera: *Camera, rectangle: *[4]i32, bar: bool, png: bool, path: []const u8) !void {
    rectangle[0] = @max(0, rectangle[0]);
    rectangle[1] = @max(0, rectangle[1]);
    rectangle[2] = @min(camera.image_width, rectangle[2]);
    rectangle[3] = @min(camera.image_height, rectangle[3]);

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

        try camera.render(writer, random, world, rectangle.*, bar);
        try buffered_stdout.flush();
    } else {
        // const png_file_name = try std.fmt.allocPrint(arena, "{s}.png", .{path});
        const ppm_file_name = try std.fmt.allocPrint(arena, "{s}.ppm", .{path});
        const ppm_file = try std.fs.cwd().createFile(ppm_file_name, .{});
        defer ppm_file.close();
        var buffered_writer = std.io.bufferedWriter(ppm_file.writer());
        const writer = buffered_writer.writer();

        try camera.render(writer, random, world, rectangle.*, bar);
        try buffered_writer.flush();

        var convert_process = std.process.Child.init(&.{ "convert", ppm_file_name, path }, arena);
        try convert_process.spawn();
        _ = try convert_process.wait();
    }
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
