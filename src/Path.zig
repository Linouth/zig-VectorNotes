const std = @import("std");

const Vec2 = @import("root").Vec2;

const Path = @This();

points: std.ArrayList(Vec2),

pub fn init(allocator: std.mem.Allocator) Path {
    return .{
        .points = std.ArrayList(Vec2).init(allocator),
    };
}

pub fn deinit(self: Path) void {
    self.points.deinit();
}

pub fn addPoint(self: Path, point: Vec2) void {
    self.points.append(point) catch unreachable;
}

pub fn slice(self: Path) []Vec2 {
    return self.points.items;
}
