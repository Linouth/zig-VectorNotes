const std = @import("std");
const glfw = @import("glfw");
const gl = @import("zgl");

const nanovg = @import("nanovg.zig");
const vec = @import("vec.zig");

const Vec2 = vec.Vec2(f64);

const WIDTH = 800;
const HEIGHT = 600;

fn keyCallback(
    window: glfw.Window,
    key: glfw.Key,
    scancode: i32,
    action: glfw.Action,
    mods: glfw.Mods
) void {
    _ = scancode;
    _ = mods;

    switch (action) {
        .press => switch (key) {
            .q => window.setShouldClose(true),
            else => {},
        },

        else => {},
    }
}

fn cursorPosCallback(window: glfw.Window, xpos: f64, ypos: f64) void {
    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    vn.mouse.pos = .{
        .x = xpos,
        .y = ypos,
    };
}

fn mouseButtonCallback(
    window: glfw.Window,
    button: glfw.mouse_button.MouseButton,
    action: glfw.Action,
    mods: glfw.Mods
) void {
    _ = mods;

    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    vn.mouse.states[@intCast(usize, @enumToInt(button))] = action;

    switch (action) {
        .press => {
            std.log.info("Mouse pressed: {} {}", .{button, vn.mouse.pos});

            switch (button) {
                .left => vn.points.append(vn.mouse.pos) catch unreachable,
                else => {},
            }

            std.log.info("Points size: {}", .{vn.points.items.len});
        },
        else => {},
    }
}

const VnCtx = struct {
    allocator: std.mem.Allocator,

    vg: nanovg.NVGwrapper,

    view: struct {
        w: u32,
        h: u32,
        origin: Vec2,
        scale: f64,
    },

    mouse: struct {
        const NUM_MOUSE_STATES = 8;

        pos: Vec2,
        pos_rc: Vec2,
        states: [NUM_MOUSE_STATES]glfw.Action,
    },

    points: std.ArrayList(Vec2),

    pub fn init(allocator: std.mem.Allocator, vg: nanovg.NVGwrapper, width: u32, height: u32) VnCtx {
        return VnCtx {
            .allocator = allocator,
            .vg = vg,
            .view = .{
                .w = width,
                .h = height,
                .origin = .{ .x = 0, .y = 0 },
                .scale = 1.0,
            },
            .mouse = .{
                .pos = undefined,
                .pos_rc = undefined,
                .states = undefined,
            },
            .points = std.ArrayList(Vec2).init(allocator),
        };
    }
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(WIDTH, HEIGHT, "VectorNotes", null, null, .{
        .context_version_major = 4,
        .context_version_minor = 5,
    });
    defer window.destroy();
    try glfw.makeContextCurrent(window);

    window.setKeyCallback(keyCallback);
    window.setMouseButtonCallback(mouseButtonCallback);
    window.setCursorPosCallback(cursorPosCallback);

    var vg = try nanovg.NVGwrapper.init(.GL3, &.{ .anti_alias, .stencil_strokes, .debug });
    defer vg.delete();

    var vn = VnCtx.init(allocator, vg, WIDTH, HEIGHT);
    window.setUserPointer(VnCtx, &vn);

    std.log.scoped(.VectorNotes).info("Starting render loop", .{});

    while (!window.shouldClose()) {
        gl.clear(.{});

        // Draw UI
        // Draw canvas

        if (vn.points.items.len > 1) {
        vg.beginFrame(WIDTH, HEIGHT, 1.0);
        vg.save();
        {
            vg.lineCap(.round);
            vg.lineJoin(.miter);
            vg.strokeWidth(2.0);
            vg.strokeColor(.{.r = 82, .g = 144, .b = 242, .a = 255});

            vg.beginPath();
            const p = vn.points.items[0];
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));
            for (vn.points.items[1..]) |point| {
                vg.lineTo(@floatCast(f32, point.x), @floatCast(f32, point.y));
            }
            vg.stroke();
        }
        vg.restore();
        vg.endFrame();
        }

        // Do logic stuff (perform 'tool' operations)

        try window.swapBuffers();
        try glfw.waitEventsTimeout(1/60);
    }
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
