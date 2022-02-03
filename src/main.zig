const std = @import("std");
const glfw = @import("glfw");
const gl = @import("zgl");

const nanovg = @import("nanovg.zig");
const vec = @import("vec.zig");
const Path = @import("Path.zig");
const BezierFit = @import("bezier_fit.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

const log = std.log.scoped(.VectorNotes);

pub const Vec2 = vec.Vec2(f64);

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

            .p => std.debug.print("{any}\n", .{vn.paths.items[vn.paths.items.len-1].points}),

            .d => vn.debug = !vn.debug,
            .b => vn.draw_bounds = !vn.draw_bounds,

            .s => {
                if (vn.stroke_scaling) {
                    log.info("Changing stroke mode to fixed", .{});
                } else {
                    log.info("Changing stroke mode to scaling", .{});
                }
                vn.stroke_scaling = !vn.stroke_scaling;
            },

            .z => if (mods.control and mods.shift) {
                vn.redo();
            } else if (mods.control) {
                vn.undo();
            },

            .c => vn.cursor_mode = !vn.cursor_mode,

            .n => vn.clearPaths(),

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
        const min_dist = 2.0;

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
            .press => {
                vn.points.clearRetainingCapacity();

                if (vn.cursor_mode) {
                    vn.selectPath(vn.view.viewToCanvas(vn.mouse.pos));
                } else {
                    vn.points.append(vn.view.viewToCanvas(vn.mouse.pos)) catch unreachable;
                }
            },

            .release => {

                if (!vn.cursor_mode) {
                    const p_prev = vn.points.items[vn.points.items.len-1];
                    const p = vn.view.viewToCanvas(vn.mouse.pos);
                    if (p_prev.x != p.x and p_prev.y != p.y) {
                        vn.points.append(p) catch unreachable;
                    }

                    if (vn.points.items.len > 1) {
                        var fitted = vn.bezier_fit.fit(vn.points.items, vn.view.scale);
                        var path = Path.initFromArray(&fitted) catch unreachable;

                        if (vn.stroke_scaling) {
                            path.setWidth(.{ .scaling = 2.0 / @floatCast(f32, vn.view.scale) });
                        } else {
                            path.setWidth(.{ .fixed = 2.0 });
                        }

                        vn.addPath(path);
                    }

                    //vn.points.clear();
                }
            },

            else => {},
        },

        .middle => switch (action) {
            .press => {
                vn.mouse.pos_pan_start = vn.mouse.pos;
            },
            else => {},
        },

        else => {},
    }
}

fn scrollCallback(window: glfw.Window, xoffset: f64, yoffset: f64) void {
    _ = xoffset;

    var vn = window.getUserPointer(*VnCtx) orelse unreachable;

    log.info("Scroll: {}", .{yoffset});
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

// TODO: Redo this temporary helper function
fn dupePathsArray(allocator: std.mem.Allocator, paths: std.ArrayList(Path)) std.ArrayList(Path) {
    var slice = allocator.alloc(Path, paths.items.len) catch unreachable;
    for (paths.items) |path, i| {
        slice[i] = path.dupe() catch unreachable;
    }
    return std.ArrayList(Path).fromOwnedSlice(allocator, slice);
}

// TODO: Redo this temporary helper function
fn freePathsArray(paths: std.ArrayList(Path)) void {
    for (paths.items) |path| {
        path.deinit();
    }
    paths.deinit();
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
    paths: std.ArrayList(Path),
    selected: std.ArrayList(usize),

    history: struct {
        buf: RingBuffer(std.ArrayList(Path), 25),
        index: usize = 0,
        outdated: bool = true,
    },

    bezier_fit: BezierFit,

    debug: bool = false,
    draw_bounds: bool = false,
    stroke_scaling: bool = false,
    cursor_mode: bool = false,

    pub fn init(allocator: std.mem.Allocator, vg: nanovg.Wrapper, width: u32, height: u32, fitter: BezierFit) VnCtx {
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
            .paths = std.ArrayList(Path).init(allocator),
            .selected = std.ArrayList(usize).init(allocator),

            .history = .{ .buf = RingBuffer(std.ArrayList(Path), 25).init() },

            .bezier_fit = fitter,
        };
    }

    pub fn deinit(self: VnCtx) void {
        self.points.deinit();

        for (self.paths.items) |path| {
            path.deinit();
        }
        self.paths.deinit();
    }

    pub fn clearPaths(self: *VnCtx) void {
        self.saveHistory();

        for (self.paths.items) |path| {
            path.deinit();
        }
        self.paths.clearRetainingCapacity();
    }

    pub fn addPath(self: *VnCtx, new_path: Path) void {
        self.saveHistory();

        // Add the new path to the pathlist
        self.paths.append(new_path) catch unreachable;

        // Flag to note that the current state is not yet in the history buffer
        self.history.outdated = true;
    }

    pub fn translatePath(self: *VnCtx, path_index: usize, translation: Vec2) void {
        self.saveHistory();

        self.paths.items[path_index] = self.paths.items[path_index].add(translation);

        self.history.index = 0;
    }

    pub fn selectPath(self: *VnCtx, pos: Vec2) void {
        const selection_range = 10;

        for (self.paths.items) |*path, i| {
            const bounds = path.bounds.?;

            // Only check the paths whose bounds overlap with the mouse pos
            if ((pos.x > bounds[0].x and pos.x < bounds[1].x) and
                (pos.y > bounds[0].y and pos.y < bounds[1].y)) {

                for (path.points) |point| {
                    if (point.dist(pos) <= selection_range) {
                        self.selected.append(i) catch unreachable;
                        break;
                    }
                }
            }
        }
    }

    /// Saves the current state to the history list
    fn saveHistory(self: *VnCtx) void {
        // Set the new startpoint of the history buffer to the current history
        // index. This is done so that you cannot redo something after adding a
        // new path.
        self.history.buf.setRelStart(@intCast(isize, self.history.index));

        // Only add the current state if we are not already using a previous
        // state.
        if (self.history.outdated) {
            // Make a copy of the current state
            var arr_new = dupePathsArray(self.allocator, self.paths);

            // Add the current state to the history buffer. If the buffer is full,
            // replace the first item. If a previous entry is overwritten, free the
            // corresponding memory.
            if (self.history.buf.pushFront(arr_new)) |prev_state| {
                freePathsArray(prev_state);
            }
        }

        // Reset history index. Essentially invalidating 'newer' (not redone)
        // entries.
        self.history.index = 0;
    }

    pub fn undo(self: *VnCtx) void {
        // Check if the current state is already in the history buffer. If it is
        // not, save the current state.
        if (self.history.outdated) {
            self.history.outdated = false;

            var arr_new = dupePathsArray(self.allocator, self.paths);
            if (self.history.buf.pushFront(arr_new)) |to_free| {
                freePathsArray(to_free);
            }
        }

        // Make sure that we stay inside the buffer bounds
        if (self.history.index >= self.history.buf.len()-1)
            return;

        self.history.index += 1;

        if (self.history.buf.get(self.history.index)) |hist| {
            freePathsArray(self.paths);
            self.paths = dupePathsArray(self.allocator, hist);
        } else {
            log.err("Could not get the proper history index..? index = {}",
                .{self.history.index});
        }
    }

    pub fn redo(self: *VnCtx) void {
        // Make sure that we can redo something.
        if (self.history.index == 0)
            return;

        self.history.index -= 1;

        if (self.history.buf.get(self.history.index)) |hist| {
            freePathsArray(self.paths);
            self.paths = dupePathsArray(self.allocator, hist);
        } else {
            log.err("Could not get the proper history index..? index = {}",
                .{self.history.index});
        }
    }

    fn drawLines(vn: VnCtx, data: []const Vec2) void {
        vn.vg.beginPath();

        const p = vn.view.canvasToView(data[0]);
        vn.vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

        for (data[1..]) |point| {
            const p_screen = vn.view.canvasToView(point);
            vn.vg.lineTo(@floatCast(f32, p_screen.x), @floatCast(f32, p_screen.y));
        }
        vn.vg.stroke();
    }

    fn drawBezier(vn: VnCtx, data: []const Vec2) void {
        vn.vg.beginPath();

        const p = vn.view.canvasToView(data[0]);
        vn.vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

        // Convert Vec2 slice into slice of [4]Vec2s and loop over it
        for (@ptrCast([*]const [3]Vec2, data[1..])[0..data.len/3]) |points| {
            const p0 = vn.view.canvasToView(points[0]);
            const p1 = vn.view.canvasToView(points[1]);
            const p2 = vn.view.canvasToView(points[2]);

            vn.vg.bezierTo(
                @floatCast(f32, p0.x), @floatCast(f32, p0.y),
                @floatCast(f32, p1.x), @floatCast(f32, p1.y),
                @floatCast(f32, p2.x), @floatCast(f32, p2.y));
        }
        vn.vg.stroke();
    }

    fn drawPath(vn: VnCtx, path: Path) void {
        switch (path.width) {
            .fixed => |width| vn.vg.strokeWidth(width),
            .scaling => |width| vn.vg.strokeWidth(@maximum(width * @floatCast(f32, vn.view.scale), 0.4)),
        }

        vn.drawBezier(path.points);
    }

    fn drawCtrl(vn: VnCtx, data: []const Vec2) void {
        {
            var i: usize = 0;
            while ((i+3) < data.len) : (i += 3) {
                const p0 = vn.view.canvasToView(data[i]);
                const p1 = vn.view.canvasToView(data[i+1]);
                const p2 = vn.view.canvasToView(data[i+2]);
                const p3 = vn.view.canvasToView(data[i+3]);

                vn.vg.strokeColor(nanovg.nvgRGBA(30, 255, 255, 200));
                vn.vg.strokeWidth(1.0);

                vn.vg.beginPath();
                vn.vg.moveTo(@floatCast(f32, p0.x), @floatCast(f32, p0.y));
                vn.vg.lineTo(@floatCast(f32, p1.x), @floatCast(f32, p1.y));
                vn.vg.stroke();

                vn.vg.beginPath();
                vn.vg.moveTo(@floatCast(f32, p2.x), @floatCast(f32, p2.y));
                vn.vg.lineTo(@floatCast(f32, p3.x), @floatCast(f32, p3.y));
                vn.vg.stroke();
            }
        }

        vn.vg.beginPath();
        for (data) |p_canvas| {
            const p = vn.view.canvasToView(p_canvas);
            vn.vg.circle(@floatCast(f32, p.x), @floatCast(f32, p.y), 3.0);
        }
        vn.vg.fillColor(nanovg.nvgRGBA(30, 255, 255, 255));
        vn.vg.fill();

        vn.vg.beginPath();
        for (data) |p_canvas| {
            const p = vn.view.canvasToView(p_canvas);
            vn.vg.circle(@floatCast(f32, p.x), @floatCast(f32, p.y), 2.0);
        }
        vn.vg.fillColor(nanovg.nvgRGBA(180, 180, 10, 255));
        vn.vg.fill();
    }

    fn drawBounds(vn: VnCtx, bounds: ?[2]Vec2) void {
        if (bounds) |b| {
            const b_lower = vn.view.canvasToView(b[0]);
            const b_upper = vn.view.canvasToView(b[1]);

            vn.vg.beginPath();
            vn.vg.rect(
                @floatCast(f32, b_lower.x),
                @floatCast(f32, b_lower.y),
                @floatCast(f32, b_upper.x - b_lower.x),
                @floatCast(f32, b_upper.y - b_lower.y));

            vn.vg.strokeColor(nanovg.nvgRGBA(30, 255, 255, 100));
            vn.vg.strokeWidth(2.0);
            vn.vg.stroke();
        } else {
            log.warn("Bounds was not initialized????", .{});
        }
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
    try glfw.swapInterval(0);

    window.setFramebufferSizeCallback(framebufferSizeCallback);
    window.setKeyCallback(keyCallback);
    window.setMouseButtonCallback(mouseButtonCallback);
    window.setCursorPosCallback(cursorPosCallback);
    window.setScrollCallback(scrollCallback);

    var vg = try nanovg.Wrapper.init(.GL3, &.{ .anti_alias, .stencil_strokes, .debug });
    defer vg.delete();

    const font_id = vg.createFont("NotoSans-Regular", "NotoSans-Regular.ttf");
    vg.fontFaceId(font_id);
    log.info("Font loaded: id={}", .{font_id});

    const fitter = BezierFit.init(allocator, .{
        .corner_thresh = std.math.pi * 0.6,
        .tangent_range = 30.0,
        .epsilon = 4.0,
        .psi = 80.0,
        .max_iter = 8,
    });

    var vn = VnCtx.init(allocator, vg, WIDTH, HEIGHT, fitter);
    window.setUserPointer(VnCtx, &vn);

    log.info("Starting render loop", .{});

    while (!window.shouldClose()) {
        gl.clear(.{ .color = true });

        // Draw UI
        // Draw canvas

        vg.beginFrame(@intToFloat(f32, vn.view.width), @intToFloat(f32, vn.view.height), 1.0);
        vg.save();
        {
            vg.lineCap(.round);
            vg.lineJoin(.miter);
            vg.strokeWidth(2.0);

            if (vn.points.items.len > 1) {
                vg.strokeColor(nanovg.nvgRGBA(82, 144, 242, 255));
                vn.drawLines(vn.points.items);
            }

            for (vn.paths.items) |path| {
                vg.strokeColor(nanovg.nvgRGBA(255, 0, 0, 255));
                vg.strokeWidth(2.0);
                vn.drawPath(path);

                if (vn.debug) {
                    vn.drawCtrl(path.points);
                }

                if (vn.draw_bounds) {
                    vn.drawBounds(path.bounds);
                }

                // Temporary to test segment code
                const segments: usize = (path.points.len-1) / 3;

                var segment: usize = 0;
                while (segment < segments) : (segment += 1) {
                    const pos = vn.view.canvasToView(path.points[segment*3]);

                    var buf: [128]u8 = undefined;
                    const txt = try std.fmt.bufPrintZ(&buf, "{d:.2}", .{path.segment_lengths[segment]});

                    _ = vg.text(@floatCast(f32, pos.x), @floatCast(f32, pos.y), txt, null);
                }

                // Temp to test path eval
                const p = vn.view.canvasToView(path.eval(0.5));

                vg.beginPath();
                vg.circle(@floatCast(f32, p.x), @floatCast(f32, p.y), 5);
                vg.fill();
            }

            for (vn.selected.items) |index| {
                vn.drawCtrl(vn.paths.items[index].points);
            }
        }
        vg.restore();
        vg.endFrame();

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
