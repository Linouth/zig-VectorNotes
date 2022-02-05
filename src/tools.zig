const std = @import("std");
const glfw = @import("glfw");
const nanovg = @import("nanovg.zig");

const VnCtx = @import("root").VnCtx;
const MouseState = @import("root").MouseState;
const Vec2 = @import("root").Vec2;
const Path = @import("Path.zig");
const BezierFit = @import("bezier_fit.zig");

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
    const RETAIN_POINTS = false;
    const MIN_DIST = 4.0;

    vn: *VnCtx,
    points: *std.ArrayList(Vec2),
    fitter: BezierFit,

    stroke_scaling: bool = false,

    pub fn init(vn: *VnCtx, points_buf: *std.ArrayList(Vec2), fitter: BezierFit) Pencil {
        return .{
            .vn = vn,
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

        switch (button) {
            .left => switch (action) {
                .press => {
                    if (RETAIN_POINTS)
                        self.points.clearRetainingCapacity();

                    try self.points.append(self.vn.view.viewToCanvas(self.vn.mouse.pos));
                },

                .release => {
                    const p_prev = self.points.items[self.points.items.len-1];
                    const p = self.vn.view.viewToCanvas(self.vn.mouse.pos);

                    // If the release position is not yet in the list, add it.
                    if (p_prev.x != p.x and p_prev.y != p.y) {
                        try self.points.append(p);
                    }

                    // If there are more than 1 items in the list, perform the
                    // fitting operation.
                    if (self.points.items.len > 1) {
                        var fitted = self.fitter.fit(self.points.items, self.vn.view.scale);
                        var path = try Path.initFromArray(&fitted);

                        if (self.stroke_scaling) {
                            path.setWidth(.{ .scaling = 2.0 / @floatCast(f32, self.vn.view.scale) });
                        } else {
                            path.setWidth(.{ .fixed = 2.0 });
                        }

                        // TODO: Should this be here? Maybe save the output
                        // somewhere and then save it on `update`
                        self.vn.addPath(path);
                    }

                    if (!RETAIN_POINTS)
                        self.points.clearRetainingCapacity();
                },

                // Ignore other actions
                else => {},
            },

            // Ignore other buttons
            else => {},
        }
    }

    /// This function adds new points to the list while dragging the mouse.
    fn onMousePos(self: *Pencil, pos: Vec2) !void {
        if (self.vn.mouse.states.left == .press) {
            const points = self.points.items;

            const mouse_canvas = self.vn.view.viewToCanvas(pos);
            const scale = self.vn.view.scale;
            if (mouse_canvas.distSqr(points[points.len-1]) >=
                (MIN_DIST*MIN_DIST / (scale*scale))) {
                try self.points.append(mouse_canvas);
            }
        }
    }

    fn draw(self: *Pencil, vg: nanovg.Wrapper) void {
        if (self.points.items.len > 1) {
            vg.strokeColor(nanovg.nvgRGBA(82, 144, 242, 255));

            // TODO: drawLines helper function (already in VnCtx)
            vg.beginPath();

            const p = self.vn.view.canvasToView(self.points.items[0]);
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

            for (self.points.items[1..]) |point| {
                const p_screen = self.vn.view.canvasToView(point);
                vg.lineTo(@floatCast(f32, p_screen.x), @floatCast(f32, p_screen.y));
            }
            vg.stroke();
        }
    }
};

pub const Selection = struct {
    const MIN_DIST = 10.0;
    const POINTS_TO_CHECK = 10;

    vn: *VnCtx,
    points: *std.ArrayList(Vec2),

    pub fn init(vn: *VnCtx, points_buf: *std.ArrayList(Vec2)) Selection {
        return .{
            .vn = vn,
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

        switch (button) {
            .left => switch (action) {
                .press => {
                    if (self.points.items.len > 0)
                        self.points.clearRetainingCapacity();

                    try self.points.append(self.vn.view.viewToCanvas(self.vn.mouse.pos));
                },

                .release => {
                    // Close the loop
                    try self.points.append(self.points.items[0]);

                    // If there is more than one item in the list, check wether
                    // there are paths inside the shape, and add them to the
                    // selected list.
                    if (self.points.items.len > 1) {
                        const bounds = calcBoundsForPoints(self.points.items);

                        for (self.vn.paths.items) |path, path_index| {
                            if (!doBoundsOverlap(path.bounds.?, bounds))
                                continue;

                            if (!self.isPathInSelection(path))
                                continue;

                            try self.vn.selected.append(path_index);
                        }
                    }

                    self.points.clearRetainingCapacity();
                },

                // Ignore other actions
                else => {},
            },

            // Ignore other buttons
            else => {},
        }
    }

    /// This function adds new points to the list while dragging the mouse.
    fn onMousePos(self: *Selection, pos: Vec2) !void {
        if (self.vn.mouse.states.left == .press) {
            const points = self.points.items;

            const mouse_canvas = self.vn.view.viewToCanvas(pos);
            const scale = self.vn.view.scale;
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

            const p = self.vn.view.canvasToView(self.points.items[0]);
            vg.moveTo(@floatCast(f32, p.x), @floatCast(f32, p.y));

            for (self.points.items[1..]) |point| {
                const p_screen = self.vn.view.canvasToView(point);
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

    // TODO: The `Path` struct should have support for more than just Bezier
    // curves. Then use the 'bounds' from that struct instead.
    fn calcBoundsForPoints(points: []const Vec2) [2]Vec2 {
        var bounds_out: ?[2]Vec2 = null;

        for (points) |point| {
            if (bounds_out) |*bounds| {
                if (point.x < bounds[0].x)
                    bounds[0].x = point.x;

                if (point.y < bounds[0].y)
                    bounds[0].y = point.y;

                if (point.x > bounds[1].x)
                    bounds[1].x = point.x;

                if (point.y > bounds[1].y)
                    bounds[1].y = point.y;
            } else {
                bounds_out = .{ point, point };
            }
        }

        return bounds_out.?;
    }

    // TODO: Should be part of `Path`
    inline fn doBoundsOverlap(b0: [2]Vec2, b1: [2]Vec2) bool {
        return isPointInBounds(b0[0], b1) or isPointInBounds(b0[1], b1);
    }

    // TODO: Should be part of `Path`
    inline fn isPointInBounds(p: Vec2, bounds: [2]Vec2) bool {
        return 
            (p.x > bounds[0].x and p.x < bounds[1].x) and
            (p.y > bounds[0].y and p.y < bounds[1].y);
    }

    fn isPathInSelection(self: *Selection, path: Path) bool {
        // Test `POINTS_TO_CHECK` samples on the bezier path, and if they
        // are all inside, assume the rest is as well.
        var i: usize = 0;
        while (i < POINTS_TO_CHECK) : (i += 1) {
            const u = 1.0 / @intToFloat(f32, POINTS_TO_CHECK) * @intToFloat(f32, i);
            const p = path.eval(u);
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
