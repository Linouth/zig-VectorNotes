const std = @import("std");
const glfw = @import("glfw");

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
    },

    pub fn init(
        pointer: anytype,
        comptime onMouseButtonFn: ?fn (ptr: @TypeOf(pointer), button: MouseButton, action: glfw.Action, mods: glfw.Mods) anyerror!void,
        comptime onMousePosFn: ?fn (ptr: @TypeOf(pointer), pos: Vec2) anyerror!void
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
        };

        return .{
            .ptr = pointer,

            .vtable = .{
                .onMouseButton = gen.onMouseButtonImpl,
                .onMousePos = gen.onMousePosImpl,
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
};

pub const Pencil = struct {
    const RETAIN_POINTS = false;
    const MIN_DIST = 4.0;

    vn: *VnCtx,
    fitter: BezierFit,

    stroke_scaling: bool = false,

    pub fn init(vn: *VnCtx, fitter: BezierFit) Pencil {
        return .{
            .vn = vn,
            .fitter = fitter,
        };
    }

    pub fn tool(self: *Pencil) Tool {
        return Tool.init(self, onMouseButton, onMousePos);
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
                        self.vn.points.clearRetainingCapacity();

                    try self.vn.points.append(self.vn.view.viewToCanvas(self.vn.mouse.pos));
                },

                .release => {
                    const p_prev = self.vn.points.items[self.vn.points.items.len-1];
                    const p = self.vn.view.viewToCanvas(self.vn.mouse.pos);

                    // If the release position is not yet in the list, add it.
                    if (p_prev.x != p.x and p_prev.y != p.y) {
                        try self.vn.points.append(p);
                    }

                    // If there are more than 1 items in the list, perform the
                    // fitting operation.
                    if (self.vn.points.items.len > 1) {
                        var fitted = self.fitter.fit(self.vn.points.items, self.vn.view.scale);
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
                        self.vn.points.clearRetainingCapacity();
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
            const points = self.vn.points.items;

            const mouse_canvas = self.vn.view.viewToCanvas(pos);
            const scale = self.vn.view.scale;
            if (mouse_canvas.distSqr(points[points.len-1]) >=
                (MIN_DIST*MIN_DIST / (scale*scale))) {
                try self.vn.points.append(mouse_canvas);
            }
        }
    }
};
