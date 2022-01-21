const std = @import("std");

const Vec2 = @import("root").Vec2;
const Path = @This();

const log = std.log.scoped(.Path);

points: std.ArrayList(Vec2),
bounds: ?[2]Vec2 = null,
selected: bool = false,

width: Width = .{ .scaling = 2.0 },

const Width = union(enum) {
    fixed: f32,
    scaling: f32,
};

pub fn init(allocator: std.mem.Allocator) Path {
    return .{
        .points = std.ArrayList(Vec2).init(allocator),
    };
}

pub fn fromArray(array: std.ArrayList(Vec2)) Path {
    var path = Path {
        .points = array,
    };

    for (path.items()) |point| {
        path.calcBounds(point);
    }

    return path;
}

pub fn deinit(self: Path) void {
    self.points.deinit();
}

pub fn clear(self: *Path) void {
    self.points.clearRetainingCapacity();
}

pub fn add(self: *Path, point: Vec2) void {
    self.calcBounds(point);

    self.points.append(point)
        catch |err| {
            log.err("Cannot add item to Path. Memory issues? Error: {}", .{err});
            std.os.exit(1);
        };
}

pub fn items(self: Path) []Vec2 {
    return self.points.items;
}

pub fn len(self: Path) usize {
    return self.points.items.len;
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
