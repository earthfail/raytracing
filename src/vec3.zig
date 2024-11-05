const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const log = std.log.scoped(.vec3);

pub const Point = Vec;
pub const Vec = struct {
    pos: [3]f32,

    pub const X: usize = 0;
    pub const Y: usize = 1;
    pub const Z: usize = 2;

    pub const error_margin: f32 = 1e-3;

    pub fn init(x: f32, y: f32, z: f32) Vec {
        return Vec{ .pos = .{ x, y, z } };
    }
    pub fn neg(self: Vec) Vec {
        var pos = self.pos;
        for (&pos) |*p| {
            p.* = -p.*;
        }
        return Vec{ .pos = pos };
    }
    pub fn add(self: *Vec, v: Vec) *Vec {
        for (&self.pos, &v.pos) |*p, q| {
            p.* += q;
        }
        return self;
    }

    pub fn mul(self: *Vec, v: Vec) *Vec {
        for (&self.pos, &v.pos) |*p, q| {
            p.* *= q;
        }
        return self;
    }
    pub fn addScalar(self: Vec, t: f32) Vec {
        var res: Vec = undefined;
        for (&res.pos, &self.pos) |*p, q| {
            p.* = q + t;
        }
        return res;
    }
    pub fn mulScalar(self: Vec, t: f32) Vec {
        var res: Vec = undefined;
        for (&res.pos, &self.pos) |*p, q| {
            p.* = q * t;
        }
        return res;
    }

    pub fn divScalar(self: Vec, t: f32) Vec {
        var res: Vec = undefined;
        for (&res.pos, &self.pos) |*p, q| {
            p.* = q / t;
        }
        return res;
    }
    pub fn div(self: *Vec, v: Vec) *Vec {
        for (&self.pos, &v.pos) |*p, q| {
            p.* /= q;
        }
        return self;
    }
    pub fn addImmutable(self: Vec, v: Vec) Vec {
        var res: Vec = undefined;
        for (&self.pos, &v.pos, &res.pos) |p, q, *s| {
            s.* = p + q;
        }
        return res;
    }
    pub fn subImmutable(self: Vec, v: Vec) Vec {
        var res: Vec = undefined;
        for (&self.pos, &v.pos, &res.pos) |p, q, *s| {
            s.* = p - q;
        }
        return res;
    }
    pub fn mulImmutable(self: Vec, v: Vec) Vec {
        var res: Vec = undefined;
        for (&self.pos, &v.pos, &res.pos) |p, q, *s| {
            s.* = p * q;
        }
        return res;
    }
    pub fn divImmultable(self: Vec, v: Vec) Vec {
        var res: Vec = undefined;
        for (&self.pos, &v.pos, &res.pos) |p, q, *s| {
            s.* = p / q;
        }
        return res;
    }
    pub fn unit(self: Vec) Vec {
        const length = self.len();
        if (length == 0) {
            return self;
        } else {
            const res = self.divScalar(length);
            assert(math.approxEqAbs(f32, res.len(), 1, error_margin));
            return res;
        }
    }
    pub fn cross(v: Vec, u: Vec) Vec {
        const x = v.pos[Y] * u.pos[Z] - v.pos[Z] * u.pos[Y];
        const y = v.pos[Z] * u.pos[X] - v.pos[X] * u.pos[Z];
        const z = v.pos[X] * u.pos[Y] - v.pos[Y] * u.pos[X];
        return .{
            .pos = .{ x, y, z },
        };
    }
    pub fn dot(self: Vec, v: Vec) f32 {
        var res: f32 = 0;
        for (&self.pos, &v.pos) |p, q| {
            res += p * q;
        }
        return res;
    }
    pub fn len_squared(self: Vec) f32 {
        var sum: f32 = 0;
        for (&self.pos) |p| {
            sum += p * p;
        }
        return sum;
    }
    pub fn len(self: Vec) f32 {
        return math.sqrt(self.len_squared());
    }
    pub fn near_zero(self: Vec) bool {
        const margin: f32 = 1e-8;
        for (&self.pos) |p| {
            if (math.approxEqAbs(f32, p, 0, margin))
                return true;
        }
        return false;
    }
    pub fn reflect(self: Vec, normal: Vec) Vec {
        assert(math.approxEqAbs(f32, normal.len(), 1, error_margin));
        return self.subImmutable(
            normal.mulScalar(2 * normal.dot(self)),
        );
    }
    pub fn refract(self: Vec, normal: Vec, etai_ratio: f32) Vec {
        // etai_ratio is the ratio of the refraction index of the start material over the refraction index of the second material
        // R_perp to the normal and R_parallel is in the direction of the normal
        // R_perp = frac{eta}{eta_tag}(R + cos(theta)normal)
        // R_parallel = -sqrt{1-|R_perp|^2}*normal
        const cos_theta: f32 = @min(1, -self.dot(normal));
        const r_out_perp = self
            .addImmutable(normal.mulScalar(cos_theta))
            .mulScalar(etai_ratio);
        const r_out_parallel = normal
            .mulScalar(-@sqrt(1 - r_out_perp.len_squared()));
        return r_out_perp.addImmutable(r_out_parallel);
    }
};
pub const RandomVecOptions = struct {
    min: f32 = 0,
    max: f32 = 1,
};
pub fn randomVector(random: std.Random, option: RandomVecOptions) Vec {
    const min = option.min;
    const max = option.max;
    const diff = max - min;
    return Vec.init(
        random.float(f32) * diff + min,
        random.float(f32) * diff + min,
        random.float(f32) * diff + min,
    );
}
pub fn randomUnitVector(random: std.Random, max_attempts: usize) Vec {
    for (0..max_attempts) |_| {
        const p = Vec.init(
            random.float(f32) * 2 - 1,
            random.float(f32) * 2 - 1,
            random.float(f32) * 2 - 1,
        );
        const length_square = p.len_squared();
        if (!math.approxEqAbs(f32, 0, length_square, 1e-6) and length_square <= 1) {
            return p.unit();
        }
    } else {
        @panic("Failed to generate random vector");
    }
}
pub fn randomVectorOnHemisphere(random: std.Random, max_attempts: usize, normal: Vec) Vec {
    const random_unit_vector = randomUnitVector(random, max_attempts);
    // TODO(Performance): Test whether switching to multiplying improves performance
    return if (Vec.dot(random_unit_vector, normal) > 0)
        random_unit_vector
    else
        random_unit_vector.neg();
}
pub fn randomVectorInUnitDisk(random: std.Random, max_attempts: usize) Vec {
    for (0..max_attempts) |_| {
        const p = Vec.init(
            random.float(f32) * 2 - 1,
            random.float(f32) * 2 - 1,
            0,
        );
        if (p.len_squared() < 1)
            return p;
    } else {
        @panic("Failed to generate vector in unit disk");
    }
}
