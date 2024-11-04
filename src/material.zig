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

pub const Dielectric = struct {
    refraction_index: f32,
    random: std.Random,
    pub fn init(random: std.Random, refraction_index: f32) Dielectric {
        return .{ .random = random, .refraction_index = refraction_index };
    }
    pub fn reflectance(cosine: f32, refraction_index: f32) f32 {
        // Use Schlick's approximation
        var r0 = (1 - refraction_index) / (1 + refraction_index);
        r0 *= r0;
        return r0 + (1 - r0) * std.math.pow(f32, (1 - cosine), 5);
    }
    pub fn scatter(ctx: *anyopaque, r_in: Ray, hit_record: *HitRecord, attenuation: *color.Rgb, scattered: *Ray) bool {
        const self: *Dielectric = @ptrCast(@alignCast(ctx));
        attenuation.* = color.Rgb.init(1, 1, 1);
        const ri: f32 = if (hit_record.front_face)
            1 / self.refraction_index
        else
            self.refraction_index;
        const unit_direction = r_in.dir.unit();
        const cos_theta: f32 = @min(1, -hit_record.normal.dot(unit_direction));
        const sin_theta: f32 = @sqrt(1 - cos_theta * cos_theta);
        const cannot_refract: bool = ri * sin_theta > 1;

        const dir: vec3.Vec = if (cannot_refract or reflectance(cos_theta, ri) > self.random.float(f32))
            unit_direction.reflect(hit_record.normal)
        else
            unit_direction.refract(hit_record.normal, ri);

        scattered.* = .{ .orig = hit_record.p, .dir = dir };
        return true;
    }
    pub fn material(self: *Dielectric) Material {
        return .{
            .ctx = self,
            .scatterFn = scatter,
        };
    }
};
