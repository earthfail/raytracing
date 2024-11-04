const std = @import("std");
const math = std.math;
const log = std.log.scoped(.hittable);

const assert = std.debug.assert;
const Ray = @import("ray.zig").Ray;
const Point = @import("vec3.zig").Point;
const color = @import("color.zig");
const Vec = @import("vec3.zig").Vec;
const Material = @import("material.zig").Material;


pub const HitRecord = struct {
    p: Point = Point.init(0, 0, 0),
    normal: Vec = Vec.init(0, 0, 0),
    mat: Material,
    t: f32 = 0,
    front_face: bool = false,

    pub fn setFaceNormal(self: *HitRecord, r: Ray, outward_normal: Vec) void {
        // NOTE(Architecture): I guess there are no modius strips in our world
        if (true) {
            assert(math.approxEqAbs(f32, outward_normal.len(), 1, 1e-3));
        } else {
            if (math.approxEqAbs(f32, outward_normal.len(), 1, 1e-3) == false) {
                std.debug.print("outward_normal len {d}, ray {any}, point: {any}\n", .{ outward_normal.len(), r, self.p });
                @panic("face normal is not a unit");
            }
        }
        self.front_face = Vec.dot(r.dir, outward_normal) < 0;
        self.normal = if (self.front_face)
            outward_normal
        else
            outward_normal.neg();
    }
};
pub fn hit(object: anytype, r: Ray, t_range: [2]f32, record: *HitRecord) bool {
    // assert(t_range[0] <= t_range[1]);
    switch (@TypeOf(object)) {
        Sphere => {
            assert(object.radius >= 0);
            const oc = Vec.subImmutable(object.center, r.orig);
            const a: f32 = r.dir.dot(r.dir);
            const b: f32 = Vec.dot(r.dir, oc);
            const c: f32 = oc.dot(oc) - object.radius * object.radius;
            const discriminant = b * b - a * c;
            if (discriminant < 0)
                return false;
            const sqrtd = math.sqrt(discriminant);
            var root: f32 = (b - sqrtd) / a;
            if (!rangeSurrounds(t_range, root)) {
                root = (b + sqrtd) / a;
                if (!rangeSurrounds(t_range, root))
                    return false;
            }
            record.t = root;
            record.p = r.at(record.t);
            const outward_normal = record.p
                .subImmutable(object.center)
                .mulScalar(1 / object.radius);
            record.mat = object.material;
            record.setFaceNormal(r, outward_normal);
            return true;
        },
        Set => {
            var hit_record: HitRecord = undefined;
            var collided: bool = false;
            var closest_hit_t = t_range[MAX];
            for (object.sphere.items) |sphere| {
                if (hit(sphere, r, [2]f32{ t_range[MIN], closest_hit_t }, &hit_record)) {
                    collided = true;
                    closest_hit_t = hit_record.t;
                    record.* = hit_record;
                }
            }
            return collided;
        },
        else => unreachable,
    }
}
pub fn sizeRange(t_range: [2]f32) f32 {
    return t_range[MAX] - t_range[MIN];
}
pub fn rangeContains(t_range: [2]f32, x: f32) bool {
    return x >= t_range[MIN] and x <= t_range[MAX];
}
pub fn rangeSurrounds(t_range: [2]f32, x: f32) bool {
    return x > t_range[MIN] and x < t_range[MAX];
}
// NOTE(Salim): I don't know if these are necessary but they were in the tutorial.
// TODO(Salim): check if used and delete if unecessary
pub const MIN = 0;
pub const MAX = 1;
pub const empty_range = [2]f32{ math.inf(f32), -math.inf(f32) };
pub const universe_range = [2]f32{ -math.inf(f32), math.inf(f32) };
pub const Sphere = struct {
    center: Point,
    radius: f32,
    material: Material,
};
pub const Set = struct {
    // TODO(Performance): move from arraylist to unmanaged array list. Situation: multiple fields, each storing its own allocator. Alternative: create a pool of objects to store in
    sphere: std.ArrayList(Sphere),
};

