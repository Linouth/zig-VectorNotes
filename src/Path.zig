const std = @import("std");

const Vec2 = @import("root").Vec2;
const Path = @This();

const log = std.log.scoped(.Path);

allocator: std.mem.Allocator,

//points: std.ArrayList(Vec2),
points: []Vec2,
segment_lengths: []f32,
length: f32 = 0,
bounds: ?[2]Vec2 = null,

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

pub fn initFromArray(array: *std.ArrayList(Vec2)) !Path {
    const points = array.toOwnedSlice();
    const alloc = array.allocator;

    var path = Path {
        .allocator = alloc,
        .points = points,
        .segment_lengths = try alloc.alloc(f32, (points.len-1) / 3),
    };

    path.calcBounds();
    path.calcSegmentLengths();

    return path;
}

pub fn deinit(self: Path) void {
    self.allocator.free(self.points);
    self.allocator.free(self.segment_lengths);
}

pub fn dupe(self: Path) !Path {
    return Path {
        .allocator = self.allocator,
        .points = try self.allocator.dupe(Vec2, self.points),
        .segment_lengths = try self.allocator.dupe(f32, self.segment_lengths),
        .length = self.length,
        .bounds = self.bounds,

        .width = self.width,
    };
}

pub fn last(self: Path) Vec2 {
    return self.points.items[self.points.items.len-1];
}

pub fn setWidth(self: *Path, width: Width) void {
    self.width = width;
}

fn calcBounds(self: *Path) void {
    for (self.points) |point| {
        self.calcBoundsForPoint(point);
    }
}

fn calcBoundsForPoint(self: *Path, point: Vec2) void {
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

pub fn calcSegmentLengths(self: *Path) void {
    const RESOLUTION = 10;
    
    var i: usize = 0;
    while (i < self.points.len-1) : (i += 3) {
        const segment_index = i / 3;
        var segment_len: f32 = 0;

        const p0 = self.points[i];
        const p1 = self.points[i+1];
        const p2 = self.points[i+2];
        const p3 = self.points[i+3];

        var u: f32 = 0;
        var j: usize = 0;
        var prev_b = evaluateBezierSegment(0, &.{p0, p1, p2, p3});
        while (j < RESOLUTION) : (j += 1) {
            u += @as(f32, 1.0) / RESOLUTION;

            const b = evaluateBezierSegment(u, &.{p0, p1, p2, p3});
            const len = prev_b.dist(b);
            segment_len += @floatCast(f32, len);

            prev_b = b;
        }

        self.segment_lengths[segment_index] = segment_len;
        self.length += segment_len;
    }
}

fn evaluateBezierSegment(u: f32, p: []const Vec2) Vec2 {
    const omu = 1 - u;

    const B0 = omu*omu*omu;
    const B1 = 3 * omu*omu * u;
    const B2 = 3 * omu * u*u;
    const B3 = u*u*u;

    return p[0].scalarMult(B0).add(
        p[1].scalarMult(B1)).add(
        p[2].scalarMult(B2)).add(
        p[3].scalarMult(B3));
}

pub fn eval(self: Path, u: f32) Vec2 {
    // TODO: Proper error
    std.debug.assert(u >= 0 and u <= 1);

    const u_rel = u * self.length;

    // Find which segment the given parameter belongs to
    var seg_i: usize = 0;
    var u_total: f32 = 0;
    while (seg_i < self.segment_lengths.len) : (seg_i += 1) {
        if (u_rel > u_total and u_rel < (u_total + self.segment_lengths[seg_i])) {
            // Given parameter falls into this segment
            break;
        }
        u_total += self.segment_lengths[seg_i];
    } else {
        // Did not break, so no segment found..???
        log.err("Could not find segment corresponding to the provided param?", .{});
        @breakpoint();
    }

    // Calculate the parameter ranging from 0 to 1 for the correct segment
    const u_seg = (u_rel - u_total) / self.segment_lengths[seg_i];
    std.debug.assert(u_seg >= 0 and u_seg <= 1);

    const p = .{
        self.points[seg_i*3],
        self.points[seg_i*3 + 1],
        self.points[seg_i*3 + 2],
        self.points[seg_i*3 + 3],
    };

    return evaluateBezierSegment(u_seg, &p);
}

//pub inline fn evaluateBezier(self: Path, u: f64) void {
//    const omu = 1 - u;
//
//    const B0 = omu*omu*omu;
//    const B1 = 3 * omu*omu * u;
//    const B2 = 3 * omu * u*u;
//    const B3 = u*u*u;
//}
