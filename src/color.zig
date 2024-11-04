const std = @import("std");
const ArrayList = std.ArrayList;
const HashMap = std.AutoArrayHashMap;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.ppm);
const Vec = @import("vec3.zig").Vec;

pub const Rgb = Vec;
pub fn outputImage(writer: anytype, width: usize, height: usize, pixels: []const Rgb) !void {
    const bw = std.io.bufferedWriter(writer);
    defer bw.flush();
    const b_writer = bw.writer();
    try b_writer.writeAll("P3\n");
    try b_writer.print("{} {}\n", .{ width, height });
    try b_writer.writeAll("255\n");
    try outputColor(writer, pixels);
}
pub fn outputColor(writer: anytype, pixel: Rgb) !void {
    try outputColors(writer, &[_]Rgb{pixel});
}
pub fn outputColors(writer: anytype, pixels: []const Rgb) !void {
    for (pixels) |pixel| {
        const r = linearToGamma(pixel.pos[0]);
        const g = linearToGamma(pixel.pos[1]);
        const b = linearToGamma(pixel.pos[2]);

        const intensity = [2]f32{ 0, 0.999 };
        const ir: u32 = @intFromFloat(255.999 * clamp(intensity, r));
        const ig: u32 = @intFromFloat(255.999 * clamp(intensity, g));
        const ib: u32 = @intFromFloat(255.999 * clamp(intensity, b));
        try writer.print("{} {} {}\n", .{ ir, ig, ib });
    }
}
fn clamp(range: [2]f32, x: f32) f32 {
    if (x > range[1]) return range[1];
    if (x < range[0]) return range[0];
    return x;
}
fn linearToGamma(linear_component: f32) f32 {
    if (linear_component > 0)
        return std.math.sqrt(linear_component);
    return 0;
}
