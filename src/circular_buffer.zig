const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.CircularBuf);

/// Modular addition. Circle around back to 0 once `size` is reached. Can
/// subtract if `b` is negative.
inline fn add(a: usize, b: isize, size: usize) usize {
    const a_int = @intCast(isize, a);
    const size_int = @intCast(isize, size);

    const ret = @mod(a_int + (size_int + b), size_int);
    return @intCast(usize, ret);
}

pub fn CircularBuf(comptime T: type, size: usize) type {
    if (size < 2)
        @compileError("CircularBuf has to have at least a size of 2.");

    return struct {
        const Self = @This();

        start: usize = 0,
        end: usize = 0,
        first: bool = true,

        items: [size]T = .{undefined} ** size,

        pub fn init() Self {
            return .{};
        }

        pub fn initFromSlice(items: []const T) Self {
            if (items.len > size)
                log.warn(
                    "CircularBuf is being initialized from a slice with more elements ({}) than the size of the buffer allows ({}). The first entries will be overwritten.",
                    .{items.len, size});

            var buf = Self {};
            for (items) |item| {
                buf.push(item);
            }

            return buf;
        }

        pub fn push(self: *Self, item: T) void {
            if (self.first) {
                // First item
                self.first = false;

                self.items[self.end] = item;
                return;
            }

            self.end = add(self.end, 1, size);

            if (self.end == self.start) {
                // Lapped
                self.start = add(self.start, 1, size);
            }

            self.items[self.end] = item;
        }

        pub fn pushFront(self: *Self, item: T) void {
            if (self.first) {
                self.push(item);
                return;
            }

            self.start = add(self.start, -1, size);

            if (self.start == self.end) {
                // Lapped
                self.end = add(self.end, -1, size);
            }

            self.items[self.start] = item;
        }

        pub fn pop(self: *Self) ?T {
            if (self.first)
                return null;

            const ret = self.items[self.end];

            if (self.start == self.end) {
                self.first = true;
            } else {
                self.end = add(self.end, -1, size);
            }

            return ret;
        }

        pub fn popFront(self: *Self) ?T {
            if (self.first)
                return null;

            const ret = self.items[self.start];

            if (self.start == self.end) {
                self.first = true;
            } else {
                self.start = add(self.start, 1, size);
            }

            return ret;
        }

        pub fn get(self: Self, abs_index: usize) ?T {
            const abs_end = add(self.end, -@intCast(isize, self.start), size);
            if (abs_index > abs_end) {
                // Unused index. Either not yet set or out of bounds.
                return null;
            }

            const index = add(self.start, @intCast(isize, abs_index), size);
            return self.items[index];
        }

        pub const CircularBufIterator = struct {
            buf: Self,
            abs_index: usize = 0,

            pub fn next(self: *@This()) ?T {
                const ret = self.buf.get(self.abs_index);
                self.abs_index += 1;
                return ret;
            }
        };

        pub fn iter(self: Self) CircularBufIterator {
            return .{
                .buf = self,
            };
        }
    };
}

test "Circular buffer iterator" {
    var buf = CircularBuf(u8, 10).init();

    buf.push(0);
    buf.push(1);
    buf.push(2);
    buf.push(3);
    buf.push(4);
    buf.push(5);
    buf.push(6);
    buf.push(7);

    var iter = buf.iter();
    var count: usize = 0;
    var sum: usize = 0;

    while (iter.next()) |item| {
        count += 1;
        sum += item;
    }

    try testing.expect(count == 8);
    try testing.expect(sum == 28);
}

test "Circular overflow then iterator" {
    var buf = CircularBuf(u8, 10).init();

    buf.push(0);
    buf.push(1);
    buf.push(2);
    buf.push(3);
    buf.push(4);
    buf.push(5);
    buf.push(6);
    buf.push(7);
    buf.push(8);
    buf.push(9);
    buf.push(10);
    try testing.expect(buf.items[0] == 10);
    try testing.expect(buf.items[1] == 1);

    try testing.expect(buf.start == 1);
    try testing.expect(buf.end == 0);

    var iter = buf.iter();
    var count: usize = 0;
    var sum: usize = 0;
    while (iter.next()) |item| {
        count += 1;
        sum += item;
    }
    try testing.expect(count == 10);
    try testing.expect(sum == 55);

    buf.pushFront(11);
    try testing.expect(buf.items[0] == 11);
    try testing.expect(buf.items[1] == 1);
    try testing.expect(buf.items[9] == 9);

    iter = buf.iter();
    sum = 0;
    while (iter.next()) |item| {
        sum += item;
    }
    try testing.expect(sum == 56);
}

test "Circular slice init" {
    var buf = CircularBuf(u8, 4).initFromSlice(&.{0, 1, 2, 3, 4});

    try testing.expect(buf.items[0] == 4);
    try testing.expect(buf.items[1] == 1);
    try testing.expect(buf.items[2] == 2);

    try testing.expect(buf.get(2).? == 3);
}

test "Circular pops" {
    var buf = CircularBuf(u8, 4).initFromSlice(&.{0, 1, 2, 3});

    try testing.expect(buf.pop().? == 3);
    try testing.expect(buf.popFront().? == 0);

    try testing.expect(buf.start == 1);
    try testing.expect(buf.end == 2);
}
