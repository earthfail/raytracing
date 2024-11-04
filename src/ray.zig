const std = @import("std");
const Vec = @import("vec3.zig").Vec;
const Point = @import("vec3.zig").Point;
pub const Ray = struct {
    orig: Point,
    dir: Vec,

    pub fn at(self: Ray, t: f32) Point {
        return Vec.addImmutable(
            self.orig,
            self.dir.mulScalar(t),
        );
    }
};
