const std = @import("std");

const Vec2 = @import("root").Vec2;
const Path = @This();

const log = std.log.scoped(.Path);

allocator: std.mem.Allocator,

//points: std.ArrayList(Vec2),
points: []Vec2,
bounds: ?[2]Vec2 = null,
selected: bool = false,

width: Width = .{ .scaling = 2.0 },

const Width = union(enum) {
    fixed: f32,
    scaling: f32,
};

pub fn init(allocator: std.mem.Allocator) Path {
    return .{
        .allocator = allocator,
        //.points = std.ArrayList(Vec2).init(allocator),
        .points = undefined,
    };
}

pub fn fromArray(array: *std.ArrayList(Vec2)) Path {
    var path = Path {
        .allocator = array.allocator,
        .points = array.toOwnedSlice(),
    };

    for (path.points) |point| {
        path.calcBounds(point);
    }

    return path;
}

pub fn deinit(self: Path) void {
    self.allocator.free(self.points);
}

pub fn dupe(self: Path) Path {
    return .{
        .allocator = self.allocator,
        .points = self.allocator.dupe(Vec2, self.points) catch unreachable,
        .bounds = self.bounds,

        .selected = self.selected,
        .width = self.width,
    };
}

pub fn last(self: Path) Vec2 {
    return self.points.items[self.points.items.len-1];
}

pub fn setWidth(self: *Path, width: Width) void {
    self.width = width;
}

fn calcBounds(self: *Path, point: Vec2) void {
    if (self.bounds) |*bounds| {
        if (point.x < bounds[0].x)
            bounds[0].x = point.x;

        if (point.y < bounds[0].y)
            bounds[0].y = point.y;

        if (point.x > bounds[1].x)
            bounds[1].x = point.x;

        if (point.y > bounds[1].y)
            bounds[1].y = point.y;
    } else {
        self.bounds = .{ point, point };
    }
}

//pub inline fn evaluateBezier(self: Path, u: f64) void {
//    const omu = 1 - u;
//
//    const B0 = omu*omu*omu;
//    const B1 = 3 * omu*omu * u;
//    const B2 = 3 * omu * u*u;
//    const B3 = u*u*u;
//}
