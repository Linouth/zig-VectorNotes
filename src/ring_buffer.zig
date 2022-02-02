const std = @import("std");
const testing = std.testing;

const log = std.log.scoped(.RingBuffer);

/// Modular addition. Circle around back to 0 once `size` is reached. Can
/// subtract if `b` is negative.
inline fn add(a: usize, b: isize, size: usize) usize {
    const a_int = @intCast(isize, a);
    const size_int = @intCast(isize, size);

    const ret = @mod(a_int + (size_int + b), size_int);
    return @intCast(usize, ret);
}

pub fn RingBuffer(comptime T: type, size: usize) type {
    if (size < 2)
        @compileError("RingBuffer has to have at least a size of 2.");

    return struct {
        const Self = @This();

        start: usize = 0,
        end: usize = 0,
        first: bool = true,

        items: [size]?T = .{null} ** size,

        pub fn init() Self {
            return .{};
        }

        pub fn initFromSlice(items: []const T) Self {
            if (items.len > size)
                log.warn(
                    "RingBuffer is being initialized from a slice with more elements ({}) than the size of the buffer allows ({}). The first entries will be overwritten.",
                    .{items.len, size});

            var buf = Self {};
            for (items) |item| {
                _ = buf.push(item);
            }

            return buf;
        }

        /// Push a new item into the back of the buffer. If the buffer is full,
        /// the first item will be replaced. If a value is overwritten, it will
        /// be returned, otherwise `null` is returned.
        pub fn push(self: *Self, item: T) ?T {
            if (self.first) {
                // First item
                self.first = false;

                self.items[self.end] = item;
                return null;
            }

            self.end = add(self.end, 1, size);

            if (self.end == self.start) {
                // Lapped
                self.start = add(self.start, 1, size);
            }

            // Check if we are overwriting a previous value
            var ret: ?T = null;
            if (self.items[self.end]) |val| {
                ret = val;
            }

            self.items[self.end] = item;
            return ret;
        }

        /// Push a new item into the front of the buffer. If the buffer is full,
        /// the last item will be replaced. If a value is overwritten, it will
        /// be returned, otherwise `null` is returned.
        pub fn pushFront(self: *Self, item: T) ?T {
            if (self.first) {
                return self.push(item);
            }

            self.start = add(self.start, -1, size);

            if (self.start == self.end) {
                // Lapped
                self.end = add(self.end, -1, size);
            }

            // Check if we are overwriting a previous value
            var ret: ?T = null;
            if (self.items[self.start]) |val| {
                ret = val;
            }

            self.items[self.start] = item;

            return ret;
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

            return ret.?;
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

            return ret.?;
        }

        /// Get the value at `rel_index` relative to `self.start`. This means
        /// that index 0 == `self.start` etc.
        pub fn get(self: Self, rel_index: usize) ?T {
            const rel_end = add(self.end, -@intCast(isize, self.start), size);
            if (rel_index > rel_end) {
                // Unused index. Either not yet set or out of bounds.
                return null;
            }

            const index = add(self.start, @intCast(isize, rel_index), size);
            return self.items[index].?;
        }

        pub fn len(self: Self) usize {
            return add(self.end, -@intCast(isize, self.start), size) + 1;
        }

        pub fn setRelStart(self: *Self, rel_index: isize) void {
            self.start = add(self.start, rel_index, size);
        }

        pub fn setRelEnd(self: *Self, rel_index: isize) void {
            self.end = add(self.end, rel_index, size);
        }

        pub const RingBufferIterator = struct {
            buf: Self,
            rel_index: usize = 0,

            pub fn next(self: *@This()) ?T {
                const ret = self.buf.get(self.rel_index);
                self.rel_index += 1;
                return ret;
            }
        };

        pub fn iter(self: Self) RingBufferIterator {
            return .{
                .buf = self,
            };
        }
    };
}

test "RingBuffer iterator" {
    var buf = RingBuffer(u8, 10).initFromSlice(&.{0, 1, 2, 3, 4, 5, 6, 7});

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

test "RingBuffer overflow then iterator" {
    var buf = RingBuffer(u8, 10).initFromSlice(&.{0, 1, 2, 3, 4, 5, 6, 7, 8});

    _ = buf.push(9);
    _ = buf.push(10);

    try testing.expect(buf.items[0].? == 10);
    try testing.expect(buf.items[1].? == 1);

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

    _ = buf.pushFront(11);
    try testing.expect(buf.items[0].? == 11);
    try testing.expect(buf.items[1].? == 1);
    try testing.expect(buf.items[9].? == 9);

    iter = buf.iter();
    sum = 0;
    while (iter.next()) |item| {
        sum += item;
    }
    try testing.expect(sum == 56);
}

test "RingBuffer slice init" {
    var buf = RingBuffer(u8, 4).initFromSlice(&.{0, 1, 2, 3, 4});

    try testing.expect(buf.items[0].? == 4);
    try testing.expect(buf.items[1].? == 1);
    try testing.expect(buf.items[2].? == 2);

    try testing.expect(buf.get(2).? == 3);
}

test "RingBuffer pops" {
    var buf = RingBuffer(u8, 4).initFromSlice(&.{0, 1, 2, 3});

    try testing.expect(buf.pop().? == 3);
    try testing.expect(buf.popFront().? == 0);

    try testing.expect(buf.start == 1);
    try testing.expect(buf.end == 2);
}

test "RingBuffer Minimal size" {
    var buf = RingBuffer(u8, 2).initFromSlice(&.{0, 1});

    try testing.expect(buf.push(2).? == 0);
    try testing.expect(buf.items[0].? == 2);
    try testing.expect(buf.items[1].? == 1);
}
