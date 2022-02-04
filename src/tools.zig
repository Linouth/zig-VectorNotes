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
