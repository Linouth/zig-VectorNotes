const std = @import("std");
const glfw = @import("glfw");
const nanovg = @import("nanovg.zig");

const VnCtx = @import("root").VnCtx;
const MouseState = @import("root").MouseState;
const Vec2 = @import("root").Vec2;
const Path = @import("Path.zig");
const BezierFit = @import("bezier_fit.zig");
const Canvas = @import("Canvas.zig");

const MouseButton = glfw.mouse_button.MouseButton;

const ToolError = error {

};

pub const Tool = struct {
    ptr: *anyopaque,

    vtable: struct {
        onMouseButton: fn (ptr: *anyopaque, button: MouseButton, action: glfw.Action, mods: glfw.Mods) anyerror!void,
        onMousePos: fn (ptr: *anyopaque, pos: Vec2) anyerror!void,
        draw: fn (ptr: *anyopaque, vg: nanovg.Wrapper) void,
    },

    pub fn init(
        pointer: anytype,
        comptime onMouseButtonFn: ?fn (ptr: @TypeOf(pointer), button: MouseButton, action: glfw.Action, mods: glfw.Mods) anyerror!void,
        comptime onMousePosFn: ?fn (ptr: @TypeOf(pointer), pos: Vec2) anyerror!void,
        comptime drawFn: ?fn (ptr: @TypeOf(pointer), vg: nanovg.Wrapper) void
    ) Tool {
        const Ptr = @TypeOf(pointer);

        const gen = struct {
            fn onMouseButtonImpl(
                ptr: *anyopaque,
                button: MouseButton,
                action: glfw.Action,
                mods: glfw.Mods
            ) !void {
                const self = @ptrCast(Ptr, @alignCast(@alignOf(Ptr), ptr));

                if (onMouseButtonFn) |func| {
                    return func(self, button, action, mods);
                }
            }

            fn onMousePosImpl(ptr: *anyopaque, pos: Vec2) !void {
                const self = @ptrCast(Ptr, @alignCast(@alignOf(Ptr), ptr));

                if (onMousePosFn) |func| {
                    return func(self, pos);
                }
            }

            fn draw(ptr: *anyopaque, vg: nanovg.Wrapper) void {
                const self = @ptrCast(Ptr, @alignCast(@alignOf(Ptr), ptr));

                if (drawFn) |func| {
                    return func(self, vg);
                }
            }
        };

        return .{
            .ptr = pointer,

            .vtable = .{
                .onMouseButton = gen.onMouseButtonImpl,
                .onMousePos = gen.onMousePosImpl,
                .draw = gen.draw,
            },
        };
    }

    pub fn cast(self: Tool, comptime T:  type) *T{
        return @ptrCast(*T, @alignCast(@alignOf(T), self.ptr));
    }

    pub fn onMouseButton(
        self: Tool,
        button: MouseButton,
        action: glfw.Action,
        mods: glfw.Mods
    ) !void {
        return self.vtable.onMouseButton(self.ptr, button, action, mods);
    }

    pub fn onMousePos(self: Tool, pos: Vec2) !void {
        return self.vtable.onMousePos(self.ptr, pos);
    }

    pub fn draw(self: Tool, vg: nanovg.Wrapper) void {
        return self.vtable.draw(self.ptr, vg);
    }
};

pub const Pencil = struct {
    const RETAIN_POINTS = true;
    const MIN_DIST = 1.0;

    mouse: *MouseState,
    view: *VnCtx.View,
    canvas: *Canvas,
    points: *std.ArrayList(Vec2),
    fitter: BezierFit,

    stroke_scaling: bool = false,

    pub fn init(mouse: *MouseState, view: *VnCtx.View, canvas: *Canvas, points_buf: *std.ArrayList(Vec2), fitter: BezierFit) Pencil {
        return .{
            .mouse = mouse,
            .view = view,
            .canvas = canvas,
            .points = points_buf,
            .fitter = fitter,
        };
    }

    pub fn tool(self: *Pencil) Tool {
        return Tool.init(self, onMouseButton, onMousePos, draw);
    }

    /// This function handles placing of a start and end point when drawing a
    /// curve. It also fits a curve to the points on release.
    fn onMouseButton(
        self: *Pencil,
        button: MouseButton,
        action: glfw.Action,
        mods: glfw.Mods
    ) !void {
        _ = mods;

        if (button == .left) switch (action) {
            .press => {
                if (RETAIN_POINTS)
                    self.points.clearRetainingCapacity();

                try self.points.append(self.view.viewToCanvas(self.mouse.pos));
            },

            .release => {
                const p_prev = self.points.items[self.points.items.len-1];
                const p = self.view.viewToCanvas(self.mouse.pos);

                // If the release position is not yet in the list, add it.
                if (p_prev.x != p.x and p_prev.y != p.y) {
                    try self.points.append(p);
                }

                // TODO: Check if this really is beneficial
                movingAvg(1, self.points.items);

                // If there are more than 1 items in the list, perform the
                // fitting operation.
                if (self.points.items.len > 1) {
                    var fitted = self.fitter.fit(self.points.items, self.view.scale);

                    self.canvas.addPath(.bezier, fitted.toOwnedSlice(), 
                        if (self.stroke_scaling)
                            .{ .scaling = 2.0 / @floatCast(f32, self.view.scale) }
                        else
                            .{ .fixed = 2.0 }
                    ) catch unreachable;
                }

                if (!RETAIN_POINTS)
                    self.points.clearRetainingCapacity();
            },

            // Ignore other actions
            else => {},
        };
    }

    /// This function adds new points to the list while dragging the mouse.
    fn onMousePos(self: *Pencil, pos: Vec2) !void {
        if (self.mouse.states.left == .press) {
            //const points = self.points.items;

            const mouse_canvas = self.view.viewToCanvas(pos);
            //const scale = self.view.scale;
            //if (mouse_canvas.distSqr(points[points.len-1]) >=
            //    (MIN_DIST*MIN_DIST / (scale*scale))) {
            //    try self.points.append(mouse_canvas);
            //}

            try self.points.append(mouse_canvas);
        }
    }

    fn draw(self: *Pencil, vg: nanovg.Wrapper) void {
        if (self.points.items.len > 1) {
            vg.strokeColor(nanovg.nvgRGBA(82, 144, 242, 255));

            // TODO: drawLines helper function (already in VnCtx)
            vg.beginPath();

            const p = self.view.canvasToView(self.points.items[0]);
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

            for (self.points.items[1..]) |point| {
                const p_screen = self.view.canvasToView(point);
                vg.lineTo(@floatCast(f32, p_screen.x), @floatCast(f32, p_screen.y));
            }
            vg.stroke();
        }
    }
};

pub const Selection = struct {
    /// The distance between sample points when drawing the selection shape.
    const MIN_DIST = 10.0;
    /// Number of points on a path to test if they are inside the selection
    /// path.
    const POINTS_TO_CHECK = 10;
    /// Sclar used on path area used to check if the bounds of a selection could
    /// possibly select the path. It means that the selected area should be at
    /// least this percentage of the path bounds.
    const BOUNDS_LIMIT_SCALAR = 0.7;

    mouse: *MouseState,
    view: *VnCtx.View,
    canvas: *Canvas,

    points: *std.ArrayList(Vec2),

    pub fn init(mouse: *MouseState, view: *VnCtx.View, canvas: *Canvas, points_buf: *std.ArrayList(Vec2)) Selection {
        return .{
            .mouse = mouse,
            .view = view,
            .canvas = canvas,
            .points = points_buf,
        };
    }

    pub fn tool(self: *Selection) Tool {
        return Tool.init(self, onMouseButton, onMousePos, draw);
    }

    fn onMouseButton(
        self: *Selection,
        button: MouseButton,
        action: glfw.Action,
        mods: glfw.Mods
    ) !void {
        _ = mods;
        
        if (button == .left) switch (action) {
            .press => {
                if (self.points.items.len > 0)
                    self.points.clearRetainingCapacity();

                try self.points.append(self.view.viewToCanvas(self.mouse.pos));
            },

            .release => {
                // If there is more than one item in the list, check wether
                // there are paths inside the shape, and add them to the
                // selected list.
                if (self.points.items.len > 1) {

                    // Close the loop
                    try self.points.append(self.points.items[0]);

                    const sel_path = Path.init(self.points.items, .lines, undefined);
                    const sel_bounds = sel_path.bounds;

                    for (self.canvas.state.paths.items(.bounds)) |path_bounds, path_i| {
                        
                        // Skip paths that are already selected.
                        if (std.mem.indexOfScalar(u32, self.canvas.selected.items, @intCast(u32, path_i))) |_|
                            continue;

                        // Skip paths whose bounds are much larger than the
                        // selection area. A seleciton path can never select a
                        // larger path than itself.
                        const path_bounds_area = path_bounds.area();
                        const sel_bounds_area = sel_bounds.area();
                        if (sel_bounds_area < path_bounds_area*BOUNDS_LIMIT_SCALAR)
                            continue;

                        // Skip paths that do not overlap with the selection
                        // path.
                        if (!sel_bounds.overlap(path_bounds))
                            continue;

                        const path = self.canvas.state.paths.get(path_i);

                        // Skip paths from which at least one test point
                        // is not inside of the selection path.
                        if (!self.isPathInSelection(path, POINTS_TO_CHECK))
                            continue;

                        self.canvas.selectPath(path_i);

                    }
                } else {
                    // This was a single click somewhere else. Deselect.
                    self.canvas.selected.clearRetainingCapacity();
                }

                self.points.clearRetainingCapacity();
            },

            // Ignore other actions
            else => {},
        };
    }

    /// This function adds new points to the list while dragging the mouse.
    fn onMousePos(self: *Selection, pos: Vec2) !void {
        if (self.mouse.states.left == .press) {
            const points = self.points.items;

            const mouse_canvas = self.view.viewToCanvas(pos);
            const scale = self.view.scale;
            if (mouse_canvas.distSqr(points[points.len-1]) >=
                (MIN_DIST*MIN_DIST / (scale*scale))) {
                try self.points.append(mouse_canvas);
            }
        }
    }

    fn draw(self: *Selection, vg: nanovg.Wrapper) void {
        if (self.points.items.len > 1) {
            vg.strokeColor(nanovg.nvgRGBA(255, 255, 255, 200));

            // TODO: drawLines helper function (already in VnCtx)
            vg.beginPath();

            const p = self.view.canvasToView(self.points.items[0]);
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

            for (self.points.items[1..]) |point| {
                const p_screen = self.view.canvasToView(point);
                vg.lineTo(@floatCast(f32, p_screen.x), @floatCast(f32, p_screen.y));
            }
            vg.stroke();
        }
    }

    /// Check whether a vertical ray from `p` to infinity intersects the
    /// line-segment from `a` to `b`. This is used to determine wether a point
    /// is inside a set of line-segments. (selection shape)
    ///
    /// let ray $V = P + t[0, 1]$ and line-segment $L = A(1-u) + Bu$.
    /// Writing the x and y equations separately, and solving for u in the x
    /// equation, and t in the y equation, results in:
    /// $$u = \frac{P_x - A_x}{B_x - A_x}$$
    /// and
    /// $$t = A_y + u(B_y - A_y) - P_y$$
    inline fn vertRayIntersectsLineSegment(p: Vec2, a: Vec2, b: Vec2) bool {
        const u = (p.x - a.x) / (b.x - a.x);

        if (u < 0 or u > 1) return false;

        const t = a.y + u*(b.y - a.y) - p.y;

        if (t < 0) return false;
        return true;
    }

    fn isPathInSelection(self: *Selection, path: Path, points_to_check: usize) bool {
        // Test `points_to_check` samples on the bezier path, and if they
        // are all inside, assume the rest is as well.
        var i: usize = 0;
        while (i < points_to_check) : (i += 1) {
            const u = 1.0 / @intToFloat(f32, points_to_check) * @intToFloat(f32, i);
            const p_err = switch (path.tag) {
                .bezier => blk: {
                    const bezier = self.canvas.state.beziers.get(path.extra_index);
                    break :blk path.eval(bezier, u);
                },

                .lines,
                .rect => path.eval(null, u),
            };
            const p = p_err catch |err|
                std.debug.panic("Error while evaluating path: {}\n", .{err});
            const points = self.points.items;

            // Check if a vertical ray passes through any of the line segments
            // from the selection path.
            var intersect_count: usize = 0;
            var seg_i: usize = 1;
            while (seg_i < points.len) : (seg_i += 1) {
                if (vertRayIntersectsLineSegment(p, points[seg_i-1], points[seg_i]))
                    intersect_count += 1;
            }

            if (intersect_count % 2 == 0) {
                // An even number of intersection. This means that the tested
                // point is *outside* of the selection path.
                return false;
            }
        }

        // All tested points are inside the selection path.
        return true;
    }
};

fn movingAvg(filter_window: usize, buf: []Vec2) void {
    var i: usize = filter_window;
    while (i < (buf.len - filter_window)) : (i += 1) {
        var avg = Vec2{.x = 0, .y = 0};
        var j: usize = i - filter_window;
        while (j <= i + filter_window) : (j += 1) {
            avg = avg.add(buf[j]);
        }
        avg = avg.scalarMult(1.0 / @intToFloat(f32, filter_window*2 + 1));

        buf[i] = avg;
    }
}
