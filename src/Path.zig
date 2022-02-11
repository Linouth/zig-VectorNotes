const std = @import("std");
const Allocator = std.mem.Allocator;

const Vec2 = @import("root").Vec2;
const Path = @This();

const log = std.log.scoped(.Path);

tag: Tag,
points: []Vec2,
bounds: Bounds,
width: Width = .{ .fixed = 2.0 },

// More specific data can be stores elsewhere. This is the index for that array,
// if applicable.
extra_index: u32 = 0,

const PathError = error {
    /// Invalid parameter passed to a function. An `err` print will give details
    /// about which parameter.
    InvalidParameter,
    /// The provided Tag is not (yet) implemented.
    /// TODO: This seems useless
    UnimplementedPathType,
};

const Bounds = [2]Vec2;

// This could also hold `WidthScaling` (encoding), but that makes changing the
// scaling dynamically difficult.
pub const Tag = enum {
    lines,
    rect,
    bezier,
};

pub const Width = union(enum) {
    scaling: f32,
    fixed: f32,
};

pub fn init(points: []Vec2, tag: Tag, width: Width) Path {
    var path = Path {
        .tag = tag,
        .points = points,
        .bounds = undefined,
        .width = width,
    };

    path.bounds = path.calcBounds();

    return path;
}

pub fn deinit(self: *Path, alloc: Allocator) void {
    alloc.free(self.points);
    self.* = undefined;
}

pub fn dupe(self: Path, alloc: Allocator) !Path {
    return Path {
        .tag = self.tag,
        .points = try alloc.dupe(Vec2, self.points),
        .bounds = self.bounds,
        .width = self.width,
    };
}

pub fn last(self: Path) Vec2 {
    return self.points[self.points.len-1];
}

pub fn setWidth(self: *Path, width: Width) void {
    self.width = width;
}

/// Naive method of calulaint path bounds by taking the furthest points from the
/// path.
fn calcBounds(self: Path) Bounds {
    var out: ?Bounds = null;
    for (self.points) |point| {
        if (out) |*bounds| {
            if (point.x < bounds[0].x)
                bounds[0].x = point.x;

            if (point.y < bounds[0].y)
                bounds[0].y = point.y;

            if (point.x > bounds[1].x)
                bounds[1].x = point.x;

            if (point.y > bounds[1].y)
                bounds[1].y = point.y;
        } else {
            out = .{ point, point };
        }
    }
    return out.?;
}

pub fn eval(self: Path, extra: anytype, u: f32) !Vec2 {
    const T = @TypeOf(extra);

    std.debug.assert(u >= 0 and u <= 1);

    switch (self.tag) {
        .lines => {},
        .rect => {},
        .bezier => {
            if (T != Bezier) {
                log.err("`extra` has to be `Bezier` type when evaling a bezier Path.", .{});
                return error.InvalidParameter;
            }

            return extra.eval(self.points, u);
        },
    }

    return error.UnimplementedPathType;
}

pub fn translate(self: *Path, translation: Vec2) void {
    for (self.points) |*point| {
        point.* = point.*.add(translation);
    }
}

pub const Bezier = struct {
    segment_lengths: []f32,
    length: f32 = 0,

    const Result = struct {
        path: Path,
        bezier: Bezier,
    };

    // TODO: Don't like this api. Think of a cleaner way to set 'options' such
    // as width.
    pub fn init(alloc: Allocator, points: []Vec2, bezier_index: usize, width: Width) !Result {
        var path = Path.init(points, .bezier, width);
        path.extra_index = @intCast(u32, bezier_index);

        var bezier = Bezier {
            .segment_lengths = try alloc.alloc(f32, (points.len-1) / 3),
            .length = undefined,
        };

        bezier.calcSegmentLengths(points);

        return Result{
            .path = path,
            .bezier = bezier,
        };
    }

    pub fn deinit(self: *Bezier, alloc: Allocator) void {
        alloc.free(self.segment_lengths);
        self.* = undefined;
    }

    pub fn dupe(self: Bezier, alloc: Allocator) !Bezier {
        return Bezier {
            .segment_lengths = try alloc.dupe(f32, self.segment_lengths),
            .length = self.length,
        };
    }

    fn calcSegmentLengths(self: *Bezier, points: []const Vec2) void {
        const RESOLUTION = 10;
        
        var i: usize = 0;
        while (i < points.len-1) : (i += 3) {
            const segment_index = i / 3;
            var segment_len: f32 = 0;

            const p0 = points[i];
            const p1 = points[i+1];
            const p2 = points[i+2];
            const p3 = points[i+3];

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

    pub fn eval(self: Bezier, points: []const Vec2, u: f32) Vec2 {
        std.debug.assert(u >= 0 and u <= 1);

        const u_rel = u * self.length;

        // Find which segment the given parameter belongs to
        var seg_i: usize = 0;
        var u_total: f32 = 0;
        while (seg_i < self.segment_lengths.len) : (seg_i += 1) {
            if (u_rel >= u_total and u_rel <= (u_total + self.segment_lengths[seg_i])) {
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
        var u_seg = (u_rel - u_total) / self.segment_lengths[seg_i];

        std.debug.assert(u_seg >= 0 and u_seg <= 1.0001);
        if (u_seg > 1.0) u_seg = 1.0; // Floats...

        const p = .{
            points[seg_i*3],
            points[seg_i*3 + 1],
            points[seg_i*3 + 2],
            points[seg_i*3 + 3],
        };

        return evaluateBezierSegment(u_seg, &p);
    }
};

