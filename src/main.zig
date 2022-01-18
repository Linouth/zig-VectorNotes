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

    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    switch (action) {
        .press => switch (key) {
            .q => window.setShouldClose(true),
            .zero => {
                vn.view.origin = .{ .x = 0, .y = 0 };
                vn.view.scale = 1.0;
            },
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

    const MouseButton = glfw.mouse_button.MouseButton;
    if (vn.mouse.states[@enumToInt(MouseButton.left)] == .press) {
        const points = vn.points.items;
        const min_dist = 8.0;

        const mouse_canvas = vn.view.viewToCanvas(vn.mouse.pos);
        if (mouse_canvas.distSqr(points[points.len-1]) >=
            (min_dist*min_dist / (vn.view.scale*vn.view.scale))) {
            vn.points.append(mouse_canvas) catch unreachable;
        }
    } else if (vn.mouse.states[@enumToInt(MouseButton.middle)] == .press) {
        const start_canvas = vn.view.viewToCanvas(vn.mouse.pos_pan_start);
        const now_canvas = vn.view.viewToCanvas(vn.mouse.pos);

        const r = now_canvas.sub(start_canvas);

        vn.view.origin.x += -r.x;
        vn.view.origin.y += -r.y;

        vn.mouse.pos_pan_start = vn.mouse.pos;
    }
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

    switch (button) {
        .left => switch (action) {
            .press => vn.points.append(vn.view.viewToCanvas(vn.mouse.pos))
                catch unreachable,
            else => {},
        },

        .middle => switch (action) {
            .press => {
                vn.mouse.pos_pan_start = vn.mouse.pos;
                std.log.info("Started panning", .{});
            },
            else => {},
        },

        else => {},
    }
}

fn scrollCallback(window: glfw.Window, xoffset: f64, yoffset: f64) void {
    _ = xoffset;

    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    std.log.info("Scroll: {}", .{yoffset});
    if (yoffset != 0.0) {
        const mouse_before = vn.view.viewToCanvas(vn.mouse.pos);

        const SCALING_FACTOR: f64 = 1.05;
        vn.view.scale *= if (yoffset > 0) SCALING_FACTOR else 1/SCALING_FACTOR;

        const mouse_after = vn.view.viewToCanvas(vn.mouse.pos);

        const r = mouse_after.sub(mouse_before);
        vn.view.origin = vn.view.origin.sub(r);
    }
}

fn framebufferSizeCallback(window: glfw.Window, width: u32, height: u32) void {
    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    gl.viewport(0, 0, width, height);

    vn.view.width = width;
    vn.view.height = height;
}

const VnCtx = struct {
    allocator: std.mem.Allocator,

    vg: nanovg.Wrapper,

    view: struct {
        width: u32,
        height: u32,
        origin: Vec2,
        scale: f64,

        pub fn viewToCanvas(self: @This(), p: Vec2) Vec2 {
            return p.scalarMult(1/self.scale).add(self.origin);
        }

        pub fn canvasToView(self: @This(), p: Vec2) Vec2 {
            return p.sub(self.origin).scalarMult(self.scale);
        }
    },

    mouse: struct {
        const NUM_MOUSE_STATES = 8;

        pos: Vec2,
        pos_pan_start: Vec2,
        states: [NUM_MOUSE_STATES]glfw.Action,
    },

    points: std.ArrayList(Vec2),

    pub fn init(allocator: std.mem.Allocator, vg: nanovg.Wrapper, width: u32, height: u32) VnCtx {
        return VnCtx {
            .allocator = allocator,
            .vg = vg,
            .view = .{
                .width = width,
                .height = height,
                .origin = .{ .x = 0, .y = 0 },
                .scale = 1.0,
            },
            .mouse = .{
                .pos = undefined,
                .pos_pan_start = undefined,
                .states = undefined,
            },
            .points = std.ArrayList(Vec2).init(allocator),
        };
    }

    pub fn deinit(self: VnCtx) void {
        self.points.deinit();
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
        .context_version_minor = 3,
    });
    defer window.destroy();
    try glfw.makeContextCurrent(window);

    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setKeyCallback(keyCallback);
    window.setMouseButtonCallback(mouseButtonCallback);
    window.setCursorPosCallback(cursorPosCallback);
    window.setScrollCallback(scrollCallback);

    var vg = try nanovg.Wrapper.init(.GL3, &.{ .anti_alias, .stencil_strokes, .debug });
    defer vg.delete();

    var vn = VnCtx.init(allocator, vg, WIDTH, HEIGHT);
    window.setUserPointer(VnCtx, &vn);

    std.log.scoped(.VectorNotes).info("Starting render loop", .{});

    while (!window.shouldClose()) {
        gl.clear(.{ .color = true });

        // Draw UI
        // Draw canvas

        if (vn.points.items.len > 1) {
        vg.beginFrame(@intToFloat(f32, vn.view.width), @intToFloat(f32, vn.view.height), 1.0);
        vg.save();
        {
            vg.lineCap(.round);
            vg.lineJoin(.miter);
            vg.strokeWidth(2.0);
            vg.strokeColor(nanovg.nvgRGBA(82, 144, 242, 255));

            vg.beginPath();
            const p = vn.view.canvasToView(vn.points.items[0]);
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));
            for (vn.points.items[1..]) |point| {
                const p_screen = vn.view.canvasToView(point);
                vg.lineTo(@floatCast(f32, p_screen.x), @floatCast(f32, p_screen.y));
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

//fn drawUi(vg: nanovg.Wrapper) void {
//
//}
//
//fn drawCanvas(vg: nanovg.Wrapper, vn: VnCtx) void {
//
//}
