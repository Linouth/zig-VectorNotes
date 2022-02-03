const std = @import("std");

const Vec2 = @import("root").Vec2;
const Points = std.ArrayList(Vec2);

const log = std.log.scoped(.BezierFit);

const BezierFit = @This();

allocator: std.mem.Allocator,
config: Config,

const FitCtx = struct {
    allocator: std.mem.Allocator,

    output: Points,
    points: []const Vec2,
    params: []f64,
    coeffs: [][4]f64,

    config: Config,

    fn init(allocator: std.mem.Allocator, points: []const Vec2, config: Config) !FitCtx {
        return FitCtx{
            .allocator = allocator,
            .output = Points.init(allocator),
            .points = points,
            .params = try allocator.alloc(f64, points.len),
            .coeffs = try allocator.alloc([4]f64, points.len),

            .config = config,
        };
    }

    fn deinit(ctx: FitCtx) void {
        ctx.allocator.free(ctx.params);
        ctx.allocator.free(ctx.coeffs);
    }

    /// Calculate the output point on the bezier curve for input point at index
    /// `index`.
    ///
    /// NOTE: This function makes use of cached bezier coefficients, a call to
    /// `fitBezier` is required first.
    fn calcBezier(ctx: FitCtx, index: usize, v0: Vec2, v1: Vec2, v2: Vec2, v3: Vec2) Vec2 {
        return v0.scalarMult(ctx.coeffs[index][0])
            .add(v1.scalarMult(ctx.coeffs[index][1]))
            .add(v2.scalarMult(ctx.coeffs[index][2]))
            .add(v3.scalarMult(ctx.coeffs[index][3]));
    }

    /// Calculate an average tangent vector using all points within a circle of
    /// `tangent_range` units.
    fn calcTangent(ctx: FitCtx, i_start: usize, i_end: usize, dir: Dir) Vec2 {
        const i_ep = switch (dir) {
            .right => i_start,
            .left => i_end,
        };

        var sum = ctx.points[i_ep];

        var i: usize = 2;
        while (i <= (i_end-i_start)) : (i += 1) {
            const p_next = ctx.points[if (dir == .right) i_ep + i else i_ep - i];

            if (ctx.points[i_ep].dist(p_next) > ctx.config.tangent_range)
                break;

            sum = sum.add(p_next);
        }
        sum = sum.scalarMult(1.0 / @intToFloat(f32, (i-1)));

        // Hacky workaround for when the sum == endpoint. This results in
        // ret = NaN.
        // TODO: Find a better solution for this
        const ret = if (sum.eql(ctx.points[i_ep]))
            ctx.points[if (dir == .right) i_ep + 1 else i_ep - 1]
                .sub(ctx.points[i_ep]).norm()
        else
            sum.sub(ctx.points[i_ep]).norm();

        if (std.math.isNan(ret.x)) @breakpoint();

        return ret;
        //return sum.sub(ctx.points[i_ep]).norm();
    }

    fn chordLengthParameterization(ctx: FitCtx, i_start: usize, i_end: usize) void {
        ctx.params[i_start] = 0.0;

        {
            var i: usize = i_start+1;
            while (i <= i_end) : (i += 1) {
                ctx.params[i] = ctx.params[i-1] + ctx.points[i].dist(ctx.points[i-1]);
            }
        }
        for (ctx.params[i_start+1..]) |*p| {
            p.* = p.* / ctx.params[i_end];
        }
    }

    /// This function makes use of the Newton-Raphson method to estimate a
    /// better set of parameters. The new parameters are saved in `ctx.params`.
    ///
    /// NOTE: it uses cached binomial coefficients, so a `fitBezier` call is
    /// required first.
    fn reparameterize(ctx: FitCtx, v0: Vec2, v1: Vec2, v2: Vec2, v3: Vec2, i_start: usize, i_end: usize) void {
        {
            var i = i_start;
            while (i <= i_end) : (i += 1) {
                const u = ctx.params[i];
                const d = ctx.points[i];

                const omu = 1-u;

                const dB0 = 3 * omu*omu;
                const dB1 = 6*u * omu;
                const dB2 = 3*u*u;

                const ddB0 = 6 * omu;
                const ddB1 = 6*u;

                const Q = ctx.calcBezier(i, v0, v1, v2, v3);

                const dQ = v1.sub(v0).scalarMult(dB0)
                    .add(v2.sub(v1).scalarMult(dB1))
                    .add(v3.sub(v2).scalarMult(dB2));

                const ddQ = v2.sub(v1.scalarMult(2)).add(v0).scalarMult(ddB0)
                    .add(v3.sub(v1.scalarMult(2)).add(v1).scalarMult(ddB1));

                const num = Q.sub(d).dot(dQ);
                const denom = dQ.dot(dQ) + Q.sub(d).dot(ddQ);

                ctx.params[i] = if (denom == 0.0) u else u - (num / denom);
            }
        }
    }

    fn fitBezier(ctx: *FitCtx, t1: Vec2, t2: Vec2, depth: usize, i_start: usize, i_end: usize) void {
        const v0 = ctx.points[i_start];
        const v3 = ctx.points[i_end];

        if (i_end - i_start == 1) {
            // Only two points

            const dist = v0.dist(v3) / 3.0;
            const v1 = v0.add(t1.scalarMult(dist));
            const v2 = v3.add(t2.scalarMult(dist));

            ctx.output.append(v1) catch unreachable;
            ctx.output.append(v2) catch unreachable;
            ctx.output.append(v3) catch unreachable;

            std.debug.assert(
                !std.math.isNan(v1.x)
                and !std.math.isNan(v2.x)
                and !std.math.isNan(v3.x)
            ); // Two points fit

            return;
        }

        var c11: f64 = 0;
        var c1221: f64 = 0;
        var c22: f64 = 0;
        var x1: f64 = 0;
        var x2: f64 = 0;

        {
            var i: usize = i_start;
            while (i <= i_end) : (i += 1) {
                const u = ctx.params[i];
                const d = &ctx.points[i];
                const b = &ctx.coeffs[i];

                const omu = 1-u;

                b[0] = omu*omu*omu;
                b[1] = 3*u * omu*omu;
                b[2] = 3*u*u * omu;
                b[3] = u*u*u;

                const A1 = t1.scalarMult(b[1]);
                const A2 = t2.scalarMult(b[2]);

                c11 += A1.dot(A1);
                c1221 += A1.dot(A2);
                c22 += A2.dot(A2);

                const bezier = ctx.calcBezier(i, v0, v0, v3, v3);

                const sub = d.sub(bezier);
                x1 += sub.dot(A1);
                x2 += sub.dot(A2);
            }
        }

        const det_c = (c11*c22 - c1221*c1221);
        var a1 = if (det_c == 0) 0 else (x1*c22 - c1221*x2) / det_c;
        var a2 = if (det_c == 0) 0 else (c11*x2 - x1*c1221) / det_c;

        // Hacky fix for wrong fits. If a1 or a2 is zero or negative, just asume
        // it is a straight line.
        // TODO: See if something better is needed. Could split the line and see
        // if it fits better.
        const alpha_err = 1.0e-6 * v0.dist(v3);
        if (a1 < alpha_err or a2 < alpha_err) {
            a1 = v0.dist(v3) / 3.0;
            a2 = a1;
        }

        const v1 = v0.add(t1.scalarMult(a1));
        const v2 = v3.add(t2.scalarMult(a2));

        if (std.math.isNan(v1.x)) @breakpoint();

        std.debug.assert(!std.math.isNan(v1.x));
        std.debug.assert(!std.math.isNan(v2.x));

        // Calculate the greatest error (distance^2) between the fitted curve
        // and input points.
        var max_err: f64 = 0.0;
        var i_max_err: usize = 0;
        {
            var i: usize = i_start;
            while (i <= i_end) : (i += 1) {
                const d = ctx.points[i];

                const p = ctx.calcBezier(i, v0, v1, v2, v3);

                const err = d.distSqr(p);
                if (err > max_err) {
                    max_err = err;
                    i_max_err = i;
                }
            }
        }

        //log.info("Max err: {}", .{@sqrt(max_err)});

        const epsilon = ctx.config.epsilon;
        const psi = ctx.config.psi;
        if (max_err < epsilon*epsilon) {
            // Error is small enough, add cruve to the output list and return.

            ctx.output.append(v1) catch unreachable;
            ctx.output.append(v2) catch unreachable;
            ctx.output.append(v3) catch unreachable;
            return;
        } else if (max_err < psi*psi and depth < ctx.config.max_iter) {
            // The error is fairly small but still too large, try to improve by
            // reparameterizing.

            ctx.reparameterize(v0, v1, v2, v3, i_start, i_end);
            ctx.fitBezier(t1, t2, depth+1, i_start, i_end);
            return;
        }

        // Error is very large. Split the curve into multiple paths and fit
        // these paths separately.

        //log.info("Splitting! err={}, i={}", .{@sqrt(max_err), i_max_err});

        var t_split = if (ctx.points[i_max_err-1].eql(ctx.points[i_max_err+1]))
            // Workaround for when the two points around max_err are the same
            ctx.points[i_max_err-1].sub(ctx.points[i_max_err]).norm()
        else
            // Take actual tangent around the trouble point
            ctx.points[i_max_err-1].sub(ctx.points[i_max_err+1]).norm();

        //var t_split = ctx.points[i_max_err-1].sub(ctx.points[i_max_err+1]).norm();

        std.debug.assert(!std.math.isNan(t_split.x));

        ctx.chordLengthParameterization(i_start, i_max_err);
        ctx.fitBezier(t1, t_split, 0, i_start, i_max_err);

        t_split = t_split.scalarMult(-1);
        ctx.chordLengthParameterization(i_max_err, i_end);
        ctx.fitBezier(t_split, t2, 0, i_max_err, i_end);
    }

    fn startFit(ctx: *FitCtx, i_start: usize, i_end: usize) void {
        const t1 = ctx.calcTangent(i_start, i_end, .right);
        const t2 = ctx.calcTangent(i_start, i_end, .left);

        std.debug.assert(!std.math.isNan(t1.x));
        std.debug.assert(!std.math.isNan(t2.x));

        ctx.chordLengthParameterization(i_start, i_end);
        ctx.fitBezier(t1, t2, 0, i_start, i_end);
    }
};

const Dir = enum {
    right,
    left,
};

pub const Config = struct {
    corner_thresh: f64,
    tangent_range: f64,
    epsilon: f64,
    psi: f64,
    max_iter: usize,
};

pub fn init(allocator: std.mem.Allocator, config: Config) BezierFit {
    return .{
        .allocator = allocator,
        .config = config,
    };
}

pub fn fit(self: BezierFit, points: []const Vec2, scale: f64) Points {
    // Apply view scale to fitting parameters
    var config = self.config;
    config.tangent_range /= scale;
    config.epsilon /= scale;
    config.psi /= scale;

    var ctx = FitCtx.init(self.allocator, points, config) catch @panic("Cannot allocate mem? Add error");
    defer ctx.deinit();

    ctx.output.append(points[0]) catch unreachable;

    log.info("Starting new bezier fit", .{});

    // Split curve at sharp corners and fit the parts separately
    var i_start: usize = 0;
    var i: usize = 1;
    while (i < points.len-1) : (i += 1) {
        // TODO: Use multiple points for the tangent (like `calcTangent`)
        const t01 = points[i-1].sub(points[i]).norm();
        const t12 = points[i+1].sub(points[i]).norm();

        const cosa = t01.dot(t12) / (t01.len() * t12.len());
        const a = std.math.acos(cosa);

        if (a < config.corner_thresh) {
            // Sharp angle, split curve

            //log.info("Sharp corner, splitting", .{});

            ctx.startFit(i_start, i);
            i_start = i;
        }
    }

    ctx.startFit(i_start, points.len-1);

    // TODO: Get rid of this once we are certain NaN bugs are gone.
    for (ctx.output.items) |p| {
        std.debug.assert(!std.math.isNan(p.x) and !std.math.isNan(p.y));
    }

    return ctx.output;
}
