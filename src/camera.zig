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
// focal_length: f32 = 1.0,
vfov: f32 = 90, // Vertical view angle in degrees
viewport_height: f32 = 2.0,
viewport_width: f32 = undefined,
camera_center: Point = undefined,
// Camera frame basis vectors: u to the right, w to the back and v up making a right hand triple (det(u,v,w) > 0)
// TODO(Architecture): collect in one array of vectors
u: Vec = undefined,
v: Vec = undefined,
w: Vec = undefined,

// parameters
look_from: Point = Point.init(0, 0, 0), // Point camera is looking from
look_at: Point = Point.init(0, 0, -1), // point camera is looking at
view_up: Vec = Vec.init(0, 1, 0), // up direction for the camera

// zig fmt: off
defocus_angle: f32 = 0, // Variation angle of rays from each pixel into the lens of a camera.
                        // we don't simulate the inside of the camera behind the lens until the sensor
focus_dist: f32 = 10,
// zig fmt: on
// TODO(Architecture): collect in one array of vectors
defocus_disk_u: Vec = undefined, // Defocus disk horizontal radius
defocus_disk_v: Vec = undefined, // Defocus disk vertical radius
pub fn init(res: *Self) void {
    // Image
    res.image_height = @max(1, @as(i32, @intFromFloat(@as(f32, @floatFromInt(res.image_width)) / res.ideal_aspect_ratio)));
    const aspect_ratio: f32 = @as(f32, @floatFromInt(res.image_width)) / @as(f32, @floatFromInt(res.image_height));
    log.debug("image width,height {},{}", .{ res.image_width, res.image_height });
    // Camera
    // res.focal_length = res.look_from.subImmutable(res.look_at).len();
    const theta: f32 = degrees2radians(res.vfov);
    const h = @tan(theta / 2);
    // res.viewport_height = 2 * h * res.focal_length;
    res.viewport_height = 2 * h * res.focus_dist;
    res.viewport_width = res.viewport_height * aspect_ratio;
    res.camera_center = res.look_from;
    log.debug("focal_length, viewport width,height {d} {d} {d}", .{ res.focus_dist, res.viewport_width, res.viewport_height });
    // Camera basis
    res.w = res.look_from.subImmutable(res.look_at).unit();
    res.u = res.view_up.cross(res.w).unit();
    res.v = res.w.cross(res.u);
    std.debug.print("u,v,w: {d} {d} {d}\n", .{ res.u.pos, res.v.pos, res.w.pos });
    // Calculate the camera defocus disk basis vectors.
    const defocus_radius = res.focus_dist * @tan(degrees2radians(res.defocus_angle / 2));
    std.debug.print("defocus_radius: {d}\n", .{defocus_radius});
    std.debug.print("defocus_angle(degrees,radians): {d}, {d}\n", .{ res.defocus_angle, degrees2radians(res.defocus_angle) });

    res.defocus_disk_u = res.u.mulScalar(defocus_radius);
    res.defocus_disk_v = res.v.mulScalar(defocus_radius);
    std.debug.print("defocus disk u,v: {d} {d}\n", .{ res.defocus_disk_u.pos, res.defocus_disk_v.pos });
}

pub fn render(self: Self, writer: anytype, random: std.Random, world: hittable.Set, rectangle: [4]i32, bar: bool) !void {

    // horizontal and vertical vectors from the top left point of the viewport
    // to the facing edges
    const viewport_u = self.u.mulScalar(self.viewport_width);
    const viewport_v = self.v.mulScalar(-self.viewport_height); // images vertical direction is "down"
    const viewport_dirs = [_]Vec{ viewport_u, viewport_v };

    const pixel_delta_u = viewport_u.divScalar(@floatFromInt(self.image_width));
    const pixel_delta_v = viewport_v.divScalar(@floatFromInt(self.image_height));
    const pixel_delta = [_]Vec{ pixel_delta_u, pixel_delta_v };

    const viewport_top_left = blk: {
        var res = self.camera_center;
        _ = res.add(Vec.neg(self.w.mulScalar(self.focus_dist)))
            .add(Vec.neg(viewport_dirs[Vec.X].mulScalar(0.5)))
            .add(Vec.neg(viewport_dirs[Vec.Y].mulScalar(0.5)));
        break :blk res;
    };
    std.debug.print("viewport top left {any}\n", .{viewport_top_left});

    const pixel00_location = blk: {
        var res = viewport_top_left;
        _ = res.add(pixel_delta[Vec.X].mulScalar(0.5))
            .add(pixel_delta[Vec.Y].mulScalar(0.5));
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
                        pixel_delta[Vec.X]
                            .mulScalar(di + offset[0]),
                    ).addImmutable(
                        pixel_delta[Vec.Y]
                            .mulScalar(dj + offset[1]),
                    );
                    const ray_origin = if (self.defocus_angle <= 0)
                        self.camera_center
                    else
                        self.defocusDiskSample(random);

                    const ray_direction = pixel_sample.subImmutable(ray_origin);
                    const ray: Ray = .{ .orig = ray_origin, .dir = ray_direction };
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
pub fn defocusDiskSample(self: Self, random: std.Random) Vec {
    const p = vec3.randomVectorInUnitDisk(random, 60);
    return self.camera_center
        .addImmutable(self.defocus_disk_u.mulScalar(p.pos[Vec.X]))
        .addImmutable(self.defocus_disk_v.mulScalar(p.pos[Vec.Y]));
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
