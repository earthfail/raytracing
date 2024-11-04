const std = @import("std");
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Semaphore = Thread.Semaphore;

const ray = @cImport({
    @cInclude("raylib.h");
    @cInclude("rcore.h");
    @cInclude("raymath.h");
    @cInclude("rlgl.h");
});

const SAMPLES_PER_PIXEL = 0;
const MAX_DEPTH = 1;
const parameters_names = [2][]const u8{ "Samples/pixel", "Max depth" };
var parameters_values = [_]u32{ 10, 10 };
var current_parameter: u8 = 0;

const State = enum { view, edit };
const Image = struct {
    texture: ray.Texture2D,
    name: [:0]const u8,
    pub fn deinit(self: Image, allocator: std.mem.Allocator) void {
        ray.UnloadTexture(self.texture);
        allocator.free(self.name);
    }
};
var images: [10]?Image = .{null} ** 10;
var current_image: u8 = 0;
var image_edge: ray.Vector2 = .{ .x = 0, .y = 0 };
var state: State = State.view;

const Rectangle = struct {
    // we only need them to be on opposite sides
    top_left: ray.Vector2,
    bottom_right: ray.Vector2,

    pub fn drawRectangle(self: Rectangle, top_left_edge: ray.Vector2) void {
        const tl = ray.Vector2Add(self.top_left, top_left_edge);
        const br = ray.Vector2Add(self.bottom_right, top_left_edge);
        const pos_x = @as(c_int, @intFromFloat(@min(tl.x, br.x)));
        const pos_y = @as(c_int, @intFromFloat(@min(tl.y, br.y)));
        const width = @as(c_int, @intFromFloat(@abs(tl.x - br.x)));
        const height = @as(c_int, @intFromFloat(@abs(tl.y - br.y)));
        ray.DrawRectangleLines(pos_x, pos_y, @intCast(width), @intCast(height), ray.YELLOW);
    }
};

var edit_section: ?Rectangle = null;

const Compilation = enum { idle, progress, finished };
var compiling_thread: ?Thread = null;
var generating_image_lock: Thread.Mutex = .{};
var semaphore: Semaphore = Semaphore{};
var exit_compiling = false;
// var compiling: Compilation = Compilation.idle;
var back_image: ?Image = undefined;
var replace_index: usize = 0;

pub fn main() !void {
    const width = 800;
    const height = 450;

    ray.SetConfigFlags(ray.FLAG_MSAA_4X_HINT | ray.FLAG_VSYNC_HINT | ray.FLAG_WINDOW_RESIZABLE);

    ray.InitWindow(width, height, "viewer for raytracing result");
    ray.SetWindowMinSize(width, height);
    defer ray.CloseWindow();

    var camera: ray.Camera2D = undefined;
    camera.zoom = 1;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const g_allocator = gpa.allocator();
    defer {
        // _ = gpa.detectLeaks();
        // const deinit_status = gpa.deinit();
        // if (deinit_status == .leak) std.testing.expect(false) catch {
        //     @panic("gpa leaked");
        // };
    }
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();
    {
        const cwd_name = try std.fs.cwd().realpathAlloc(g_allocator, ".");
        std.debug.print("cwd_name \"{s}\"\n", .{cwd_name});
        g_allocator.free(cwd_name);
    }

    // const image_name: []const u8 = stdin.readUntilDelimiterAlloc(temp_allocator, '\n', 512) catch "image.png";
    const image_name = try g_allocator.dupeZ(u8, "image.png");
    images[0] = try loadImage(image_name);

    while (!ray.WindowShouldClose()) {
        const screen_width = ray.GetScreenWidth();
        const screen_height = ray.GetScreenHeight();

        if (ray.IsKeyPressed(ray.KEY_Q)) {
            state = switch (state) {
                .view => .edit,
                .edit => .view,
            };
        } else if (ray.IsKeyPressed(ray.KEY_R)) {
            if (images[current_image]) |*image| {
                ray.UnloadTexture(image.texture);
                image.* = try loadImage(image.name);
            }
            edit_section = null;
            std.debug.print("reload image\n", .{});
        } else if (ray.IsKeyPressed(ray.KEY_A)) {
            if (edit_section) |section| {
                std.debug.print("rection {d:3},{d:3} : {d:3},{d:3}\n", .{
                    section.top_left.x,
                    section.top_left.y,
                    section.bottom_right.x,
                    section.bottom_right.y,
                });
            }
            if (images[current_image]) |image| {
                std.debug.print("{s}: widthxheight {d:2},{d:2}\n", .{ image.name, image.texture.width, image.texture.height });
                const edge = topLeftEdge(screen_width, screen_height, image.texture.width, image.texture.height);
                std.debug.print("image_top_left edge: {d:3},{d:3}\n", .{ edge[0], edge[1] });
            }
        }
        switch (state) {
            .view => {
                if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
                    var delta = ray.GetMouseDelta();
                    delta = ray.Vector2Scale(delta, -1 / camera.zoom);
                    camera.target = ray.Vector2Add(camera.target, delta);
                } else {
                    const key = ray.GetCharPressed();
                    if (key >= '0' and key <= '9') {
                        current_image = if (key != '0') @as(u8, @intCast(key)) - '1' else 10;
                    }
                }
                {
                    const wheel = ray.GetMouseWheelMove();
                    if (wheel != 0) {
                        const mouse_world_pos = ray.GetScreenToWorld2D(ray.GetMousePosition(), camera);
                        camera.offset = ray.GetMousePosition();
                        camera.target = mouse_world_pos;
                        const zoom_inc: f32 = 0.125;
                        camera.zoom += wheel * zoom_inc;
                        camera.zoom = @max(zoom_inc, camera.zoom);
                    }
                }
            },
            .edit => {
                var parameter_changed = true;
                if (ray.IsKeyPressed(ray.KEY_DOWN)) {
                    current_parameter = @mod((current_parameter - 1), @as(u8, @intCast(parameters_values.len)));
                } else if (ray.IsKeyPressed(ray.KEY_UP)) {
                    current_parameter = @mod((current_parameter + 1), @as(u8, @intCast(parameters_values.len)));
                } else if (ray.IsKeyPressed(ray.KEY_RIGHT)) {
                    parameters_values[current_parameter] += 10;
                } else if (ray.IsKeyPressed(ray.KEY_LEFT)) {
                    parameters_values[current_parameter] = @intCast(@max(@as(i32, @intCast(parameters_values[current_parameter])) - 10, 0));
                } else if (ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) {
                    parameter_changed = false;
                    const top_left = int2Vector2(if (images[current_image]) |image|
                        topLeftEdge(screen_width, screen_height, image.texture.width, image.texture.height)
                    else
                        [2]c_int{ 0, 0 });

                    const mouse_pos = ray.Vector2Subtract(
                        ray.GetScreenToWorld2D(ray.GetMousePosition(), camera),
                        top_left,
                    );

                    if (edit_section) |*rect| {
                        const dis_top_left = ray.Vector2DistanceSqr(mouse_pos, rect.top_left);
                        const dis_bottom_right = ray.Vector2DistanceSqr(mouse_pos, rect.bottom_right);
                        const margin = 1000;
                        if (dis_top_left > margin and dis_bottom_right > margin) {
                            rect.* = Rectangle{ .top_left = mouse_pos, .bottom_right = mouse_pos };
                        } else if (dis_top_left < dis_bottom_right) {
                            rect.top_left = mouse_pos;
                        } else {
                            rect.bottom_right = mouse_pos;
                        }
                    } else {
                        edit_section = Rectangle{ .top_left = mouse_pos, .bottom_right = mouse_pos };
                    }
                } else {
                    const key = ray.GetCharPressed();
                    if (key >= '0' and key <= '9') {
                        current_image = if (key != '0') @as(u8, @intCast(key)) - '1' else 10;
                        if (generating_image_lock.tryLock()) {
                            generating_image_lock.unlock();

                            replace_index = current_image;
                            if (compiling_thread) |_| {
                                std.debug.print("thread is here\n", .{});
                                semaphore.post();
                            } else {
                                std.debug.print("new Thread\n", .{});
                                semaphore.post();
                                compiling_thread = try Thread.spawn(.{}, generateImage, .{ g_allocator, &replace_index, &back_image });
                                compiling_thread.?.detach();
                            }
                        }
                    }
                }
            },
        }
        // DRAW
        {
            ray.BeginDrawing();
            defer ray.EndDrawing();
            ray.ClearBackground(ray.WHITE);

            ray.BeginMode2D(camera);
            defer ray.EndMode2D();

            if (images[current_image]) |image| {
                const top_left = topLeftEdge(screen_width, screen_height, image.texture.width, image.texture.height);
                ray.DrawTexture(
                    image.texture,
                    top_left[0],
                    top_left[1],
                    ray.WHITE,
                );
                if (edit_section) |section| {
                    section.drawRectangle(int2Vector2(top_left));
                }
            } else {
                ray.DrawText(
                    \\        Select an image
                    \\ Q: switch between edit and view
                    \\ R: reset image
                    \\ A: print square coordinates
                    \\ 1..9: view image by number
                    \\ <> (arrow key): modify value
                    \\ ^v (arrow key): change focus
                , @divFloor(screen_width, 2) - 5 * 31, @divFloor(screen_height, 2) - 10 * 7, 20, ray.BLUE);
            }

            {
                const screen_bottom_left = ray.GetScreenToWorld2D(.{ .x = 0, .y = @floatFromInt(screen_height) }, camera);
                ray.rlPushMatrix();
                defer ray.rlPopMatrix();
                ray.rlTranslatef(screen_bottom_left.x, screen_bottom_left.y, 0);
                ray.rlScalef(1 / camera.zoom, 1 / camera.zoom, 1);

                for (&parameters_names, &parameters_values, 1..) |param, val, i| {
                    const text = try std.fmt.allocPrintZ(temp_allocator, "{s} {d:3}", .{ param, val });
                    const color_text = if (state == .edit and i - 1 == current_parameter) ray.GREEN else ray.RED;

                    ray.DrawText(text, 5, -30 * @as(c_int, @intCast(i)), 20, color_text);
                }
                {
                    const text = try std.fmt.allocPrintZ(temp_allocator, "c: {d:3}, r: {d:3}", .{ current_image, replace_index });
                    ray.DrawText(text, 5, -30 * @as(c_int, @intCast(parameters_values.len + 1)), 20, ray.RED);
                }
            }
        }
        if (generating_image_lock.tryLock()) {
            if (back_image) |new_image| {
                if (images[replace_index]) |old_image| {
                    old_image.deinit(g_allocator);
                }
                images[replace_index] = new_image;
                back_image = null;
            }
            generating_image_lock.unlock();
        }
    }
    for (&images) |image| {
        if (image) |img| {
            img.deinit(g_allocator);
        }
    }
}

fn loadImage(name: [:0]const u8) !Image {
    const texture = ray.LoadTexture(name);

    return .{ .name = name, .texture = texture };
}
// TODO(Interface): replace the dumb [2]c_int
fn topLeftEdge(screen_width: c_int, screen_height: c_int, image_width: c_int, image_height: c_int) [2]c_int {
    return .{
        @divFloor(screen_width, 2) - @divFloor(image_width, 2),
        @divFloor(screen_height, 2) - @divFloor(image_height, 2),
    };
}
fn int2Vector2(offset: [2]c_int) ray.Vector2 {
    return .{
        .x = @floatFromInt(offset[0]),
        .y = @floatFromInt(offset[1]),
    };
}
fn generateImage(allocator: std.mem.Allocator, back_index: *usize, replace_image: *?Image) void {
    var i: usize = 1;
    while (true) : (i += 1) {
        semaphore.wait();
        {
            generating_image_lock.lock();
            defer generating_image_lock.unlock();
            std.debug.print("generating number {}, enter image name:\n", .{i});
            const image_name = std.fmt.allocPrintZ(allocator, "test{d:0>2}.png", .{back_index.*}) catch {
                std.debug.print("couldn't duplicate string\n", .{});
                return;
            };
            // const image_name =
            //     allocator.dupeZ(
            //     u8,
            //     if (images[back_index.*]) |old_image|
            //         old_image.name
            //     else
            //         stdin.readUntilDelimiterAlloc(allocator, '\n', 512) catch |err| {
            //             std.debug.print("couldn't read name: {}\n", .{err});
            //             return;
            //         },
            // ) catch |err| {
            //     std.debug.print("couldn't duplicate string: {}\n", .{err});
            //     return;
            // };
            std.debug.print("image_name: \"{s}\", {} \n", .{ image_name, if (std.meta.sentinel(@TypeOf(image_name))) |_| 1 else 0 });
            rayTracing(allocator, image_name) catch |err| {
                std.debug.print("failed to raytrace image \"{s}\": {}\n", .{ image_name, err });
                return;
            };

            replace_image.* = Image{ .name = image_name, .texture = ray.LoadTexture(image_name) };
            // replace_image.* = loadImage(image_name) catch {
            //     std.debug.print("failed to load image\n", .{});
            //     return;
            // };
            std.debug.print("Finished generating\n", .{});
        }
    }
    std.debug.print("generate image stopped\n", .{});
}
fn rayTracing(allocator: std.mem.Allocator, image_name: []const u8) !void {
    const samples = try std.fmt.allocPrint(allocator, "{d}", .{parameters_values[SAMPLES_PER_PIXEL]});
    const depth = try std.fmt.allocPrint(allocator, "{d}", .{parameters_values[MAX_DEPTH]});
    const basic_process_args = [_][]const u8{
        "./zig-out/bin/raytracing",
        "--samples",
        samples,
        "--depth",
        depth,
        "--png",
        image_name,
    };
    const process_args = if (edit_section) |section| sct_if: {
        const dimensions = try std.fmt.allocPrint(allocator, "{d} {d} {d} {d}", .{
            section.top_left.x,     section.top_left.y,
            section.bottom_right.x, section.bottom_right.y,
        });
        var args = std.ArrayList([]const u8).init(allocator);
        try args.appendSlice(&basic_process_args);
        try args.append("--rect");
        try args.append(dimensions);
        break :sct_if try args.toOwnedSlice();
    } else &basic_process_args;
    defer if (edit_section) |_| {
        allocator.free(process_args[process_args.len - 1]);
        allocator.free(process_args);
    };
    std.debug.print("arguments: ", .{});
    for (process_args) |arg| {
        std.debug.print("{s} ", .{arg});
    }
    std.debug.print("\n", .{});
    var build_process = std.process.Child.init(process_args, allocator);
    // build_process.stdout_behavior = .Pipe;
    // const output_file = try std.fs.cwd().createFile(image_name, .{});
    // defer output_file.close();
    // const output_handle = output_file.handle;

    try build_process.spawn();
    // const build_handle = build.process.stdout.?.handle;
    // {
    //     var offset: u64 = 0;
    //     cfr_loop: while (true) {
    //         const amt = try std.posix.copy_file_range(build_handle, offset, output_handle, offset, std.math.maxInt(u32), 0);
    //         if (amt == 0) break :cfr_loop;
    //         offset += amt;
    //     }
    // }
    _ = try build_process.wait();

    allocator.free(samples);
    allocator.free(depth);
}
