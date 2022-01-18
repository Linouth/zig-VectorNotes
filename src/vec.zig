pub fn Vec2(comptime T: type) type {

    return struct {
        const Self = @This();

        x: T,
        y: T,

        pub fn add(v0: Self, v1: Self) Self {
            return Self {
                .x = v0.x + v1.x,
                .y = v0.y + v1.y,
            };
        }

        pub fn sub(v0: Self, v1: Self) Self {
            return Self {
                .x = v0.x - v1.x,
                .y = v0.y - v1.y,
            };
        }

        pub fn mult(v0: Self, v1: Self) Self {
            return Self {
                .x = v0.x * v1.x,
                .y = v0.y * v1.y,
            };
        }

        pub fn scalarMult(v: Self, s: T) Self {
            return Self {
                .x = v.x * s,
                .y = v.y * s,
            };
        }

        pub fn dot(v0: Self, v1: Self) T {
            return v0.x*v1.x + v0.y*v1.y;
        }

        pub fn cross(v0: Self, v1: Self) T {
            return v0.x*v1.y - v0.y*v1.x;
        }

        pub fn dist(v0: Self, v1: Self) T {
            return @sqrt(v0.distSqr(v1));
        }

        pub fn distSqr(v0: Self, v1: Self) T {
            const x = v0.x - v1.x;
            const y = v0.y - v1.y;
            return x*x + y*y;
        }

        pub fn len(v: Self) T {
            return @sqrt(v.dot(v));
        }

        pub fn norm(v: Self) Self {
            const l = v.len();
            return Self {
                .x = v.x / l,
                .y = v.y / l,
            };
        }

        pub fn tangent(v0: Self, v1: Self) Self {
            return v1.sub(v0).norm();
        }
    };
}

