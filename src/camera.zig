const std = @import("std");
const color = @import("color.zig");
const Vec = @import("vec3.zig").Vec;
const vec3 = @import("vec3.zig");
const Point = @import("vec3.zig").Point;
const Ray = @import("ray.zig").Ray;
const hittable = @import("hittable.zig");
const assert = std.debug.assert;
const log = std.log.scoped(.camera);

const Self = @This();
// Image
ideal_aspect_ratio: f32 = 16.0 / 9.0,
image_width: i32 = 400,
image_height: i32 = undefined,

// Anti Aliasing
samples_per_pixel: i32 = 10,
// Bouncing lights
max_depth: u8 = 10,
// Camera
focal_length: f32 = 1.0,
vfov: f32 = 90, // Vertical view angle in degrees
viewport_height: f32 = 2.0,
viewport_width: f32 = undefined,
camera_center: Point = undefined,

pub fn init() Self {
    var res: Self = .{};
    // Image
    res.image_height = @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(res.image_width)) / res.ideal_aspect_ratio)));
    const aspect_ratio: f32 = @as(f32, @floatFromInt(res.image_width)) / @as(f32, @floatFromInt(res.image_height));
    log.debug("image width,height {},{}", .{ res.image_width, res.image_height });
    // Camera
    res.focal_length = 1.0;
    const theta: f32 = degrees2radians(res.vfov);
    const h = @tan(theta / 2);
    res.viewport_height = 2 * h * res.focal_length;
    res.viewport_width = res.viewport_height * aspect_ratio;
    res.camera_center = Point.init(0, 0, 0);
    log.debug("focal_length, viewport width,height {d} {d} {d}", .{ res.focal_length, res.viewport_width, res.viewport_height });

    return res;
}
pub fn render(self: Self, writer: anytype, random: std.Random, world: hittable.Set, rectangle: [4]i32, bar: bool) !void {

    // horizontal and vertical vectors from the top left point of the viewport
    // to the facing edges
    const viewport_u = Vec{ .pos = .{ self.viewport_width, 0, 0 } };
    const viewport_v = Vec{ .pos = .{ 0, -self.viewport_height, 0 } };
    const viewport_dirs = [_]Vec{ viewport_u, viewport_v };

    const pixel_delta_u = viewport_u.divScalar(@floatFromInt(self.image_width));
    const pixel_delta_v = viewport_v.divScalar(@floatFromInt(self.image_height));
    const pixel_delta_dirs = [_]Vec{ pixel_delta_u, pixel_delta_v };

    const viewport_top_left = blk: {
        var res = self.camera_center;
        const camera_to_viewport = Vec{ .pos = .{ 0, 0, -self.focal_length } };
        _ = res.add(camera_to_viewport)
            .add(Vec.neg(viewport_dirs[Vec.X].mulScalar(0.5)))
            .add(Vec.neg(viewport_dirs[Vec.Y].mulScalar(0.5)));
        break :blk res;
    };
    log.debug("viewport top left {any}", .{viewport_top_left});

    const pixel00_location = blk: {
        var res = viewport_top_left;
        _ = res.add(pixel_delta_dirs[Vec.X].mulScalar(0.5))
            .add(pixel_delta_dirs[Vec.Y].mulScalar(0.5));
        break :blk res;
    };
    // Anti aliasing
    const pixel_samples_scale: f32 = 1 / @as(f32, @floatFromInt(self.samples_per_pixel));

    try writer.writeAll("P3\n");
    try writer.print("{} {}\n", .{ self.image_width, self.image_height });
    try writer.writeAll("255\n");
    for (0..@intCast(self.image_height)) |j| {
        if (bar) {
            std.debug.print("\rScanlines remainging: {d:3}", .{@as(usize, @intCast(self.image_height)) - j});
        }
        for (0..@intCast(self.image_width)) |i| {
            const di: f32 = @floatFromInt(i);
            const dj: f32 = @floatFromInt(j);
            var pixel_color = color.Rgb.init(0, 0, 0);
            if (i >= rectangle[0] and i <= rectangle[2] and j >= rectangle[1] and j <= rectangle[3]) {
                for (0..@intCast(self.samples_per_pixel)) |_| {
                    const offset = [2]f32{ random.float(f32), random.float(f32) };
                    const pixel_sample =
                        pixel00_location
                        .addImmutable(
                        pixel_delta_dirs[Vec.X]
                            .mulScalar(di + offset[0]),
                    ).addImmutable(
                        pixel_delta_dirs[Vec.Y]
                            .mulScalar(dj + offset[1]),
                    );
                    const ray_direction = pixel_sample.subImmutable(self.camera_center);
                    const ray: Ray = .{ .orig = self.camera_center, .dir = ray_direction };
                    var attenuation = color.Rgb.init(1, 1, 1);
                    const color_sample = rayColor(
                        ray,
                        world,
                        random,
                        self.max_depth,
                        &attenuation,
                    );
                    _ = pixel_color.add(color_sample);
                }
            }
            try color.outputColor(
                writer,
                pixel_color.mulScalar(pixel_samples_scale),
            );
        }
    }
    if (bar) {
        std.debug.print("\rDone.                           \n", .{});
    }
}
pub fn rayColor(r: Ray, world: hittable.Set, random: std.Random, depth: u8, attenuation: *color.Rgb) color.Rgb {
    if (depth == 0) {
        return color.Rgb.init(0, 0, 0);
    }
    var record: hittable.HitRecord = undefined;
    const white = color.Rgb.init(1, 1, 1);
    const margin: f32 = 1e-3; // to ignore intersection that are too close and mitigate floating point errors
    if (hittable.hit(world, r, [_]f32{ margin, std.math.inf(f32) }, &record)) {
        var scattered_ray: Ray = undefined;
        var scattered_attenuation: color.Rgb = undefined;
        const scattered: bool = record.mat.scatter(r, &record, &scattered_attenuation, &scattered_ray);
        if (scattered) {
            return rayColor(scattered_ray, world, random, depth - 1, attenuation.mul(scattered_attenuation));
        }
        return color.Rgb.init(0, 0, 0);
    }
    const unit = r.dir.unit();
    const a: f32 = 0.5 * (unit.pos[Vec.Y] + 1.0);
    const blue = color.Rgb.init(0.5, 0.7, 1);
    return Vec.addImmutable(
        white.mulScalar(1 - a),
        blue.mulScalar(a),
    ).mulImmutable(attenuation.*);
}

pub fn updateWidth(self: *Self, width: i32) void {
    self.image_width = @max(1, width);
    self.image_height = @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(self.image_width)) / self.ideal_aspect_ratio)));
}
pub fn updateHeight(self: *Self, height: i32) void {
    self.image_height = height;
    self.image_width = @max(1, @as(i32, @intFromFloat(self.image_height * self.ideal_aspect_ratio)));
}
pub fn updateViewportWidth(self: *Self, width: f32) void {
    self.viewport_width = width;
    const inv_aspect_ratio: f32 = @as(f32, @floatFromInt(self.image_height)) / @as(f32, @floatFromInt(self.image_width));
    self.viewport_height = self.viewport_width * inv_aspect_ratio;
}
pub fn updateViewportHeight(self: *Self, height: f32) void {
    self.viewport_height = height;
    const aspect_ratio: f32 = @as(f32, @floatFromInt(self.image_width)) / @as(f32, @floatFromInt(self.image_height));
    self.viewport_width = self.viewport_height * aspect_ratio;
}

pub fn degrees2radians(degree: f32) f32 {
    return degree * std.math.rad_per_deg;
}
