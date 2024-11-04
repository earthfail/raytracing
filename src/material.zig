const std = @import("std");
const math = std.math;
const log = std.log.scoped(.material);

const assert = std.debug.assert;
const Ray = @import("ray.zig").Ray;
const Point = @import("vec3.zig").Point;
const color = @import("color.zig");
const vec3 = @import("vec3.zig");
const HitRecord = @import("hittable.zig").HitRecord;

pub const Material = struct {
    // NOTE(Architecture): consider moving albedo into material because Lambertian and metal uses them.
    ctx: *anyopaque,
    scatterFn: *const fn (ctx: *anyopaque, r_in: Ray, hit_record: *HitRecord, attenuation: *color.Rgb, scattered: *Ray) bool,

    pub fn scatter(self: Material, r_in: Ray, hit_record: *HitRecord, attenuation: *color.Rgb, scattered: *Ray) bool {
        return self.scatterFn(self.ctx, r_in, hit_record, attenuation, scattered);
    }
};

pub const Lambertian = struct {
    // NOTE(Salim): albedo is such a cool name.
    albedo: color.Rgb,
    random: std.Random,
    pub fn init(random: std.Random, albedo: color.Rgb) Lambertian {
        return .{ .albedo = albedo, .random = random };
    }
    pub fn scatter(ctx: *anyopaque, r_in: Ray, hit_record: *HitRecord, attenuation: *color.Rgb, scattered: *Ray) bool {
        _ = r_in;
        const lamber_ptr: *Lambertian = @ptrCast(@alignCast(ctx));
        var direction = vec3.randomUnitVector(lamber_ptr.random, 60);
        _ = direction.add(hit_record.normal);

        if (direction.near_zero()) {
            direction = hit_record.normal;
        }

        scattered.* = .{ .orig = hit_record.p, .dir = direction };
        attenuation.* = lamber_ptr.albedo;
        return true;
    }
    pub fn material(self: *Lambertian) Material {
        return .{
            .ctx = self,
            .scatterFn = scatter,
        };
    }
};

pub const Metal = struct {
    albedo: color.Rgb,
    // fuzz is how much the reflected ray can deviate from the simple model
    fuzz: f32,
    random: std.Random,
    pub fn init(random: std.Random, albedo: color.Rgb, fuzz: f32) Metal {
        return .{ .albedo = albedo, .random = random, .fuzz = fuzz };
    }
    pub fn scatter(ctx: *anyopaque, r_in: Ray, hit_record: *HitRecord, attenuation: *color.Rgb, scattered: *Ray) bool {
        const self_ptr: *Metal = @ptrCast(@alignCast(ctx));
        const ideal_reflected = r_in.dir.reflect(hit_record.normal);
        const fuzzyness = vec3.randomUnitVector(self_ptr.random, 60).mulScalar(self_ptr.fuzz);
        const reflected = ideal_reflected.unit().addImmutable(fuzzyness);
        scattered.* = .{ .orig = hit_record.p, .dir = reflected };
        attenuation.* = self_ptr.albedo;
        return scattered.dir.dot(hit_record.normal) > 0;
    }
    pub fn material(self: *Metal) Material {
        return .{
            .ctx = self,
            .scatterFn = scatter,
        };
    }
};
