const std = @import("std");
const Allocator = std.mem.Allocator;

const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const Path = @import("Path.zig");
const Vec2 = @import("root").Vec2;

const log = std.log.scoped(.Canvas);

const Canvas = @This();

allocator: Allocator,

/// The current state of the canvas. This holds all paths, and additional
/// required data. Saving to a file or storing the state for undoing makes a
/// copy of this struct.
state: State = .{},
/// The indices of all paths that are currently selected. We're assuming a max
/// of 2**32 paths.
selected: std.ArrayListUnmanaged(u32) = .{},

/// Holds copies of the canvas `State`
history: struct {
    buf: RingBuffer(State, 25) = .{},
    /// The current history index. If this is greater than 0 it means that we
    /// are currently in an 'undone' state. Saving a new state will set the end
    /// of the ringbuffer to this index, and thus clear all newer states.
    index: usize = 0,

    /// Flag to make sure that `undo` will save the current state before
    /// undoing.
    outdated: bool = true,
} = .{},

const State = struct {
    // TODO: Stores raw data instead of whole MultiArrayList when saving state?
    // Check how much memory this would save.
    paths: std.MultiArrayList(Path) = .{},
    beziers: std.MultiArrayList(Path.Bezier) = .{},

    pub fn deinit(self: *State, alloc: Allocator) void {
        for (self.paths.items(.points)) |*points| {
            alloc.free(points.*);
        }
        self.paths.deinit(alloc);

        for (self.beziers.items(.segment_lengths)) |*segment_lengths| {
            alloc.free(segment_lengths.*);
        }
        self.beziers.deinit(alloc);
    }

    pub fn clear(self: *State, alloc: Allocator) void {
        self.deinit(alloc);
        self.paths = std.MultiArrayList(Path){};
        self.beziers = std.MultiArrayList(Path.Bezier){};
    }

    pub fn dupe(self: State, alloc: Allocator) !State {
        // Clones the MultiArrayLists and then dupes the allocated slices inside
        // the arraylists.

        var new_paths = try self.paths.clone(alloc);
        for (new_paths.items(.points)) |*points| {
            points.* = try alloc.dupe(Vec2, points.*);
        }

        var new_beziers = try self.beziers.clone(alloc);
        for (new_beziers.items(.segment_lengths)) |*segment_lengths| {
            segment_lengths.* = try alloc.dupe(f32, segment_lengths.*);
        }

        return State {
            .paths = new_paths,
            .beziers = new_beziers,
        };
    }
};

pub fn init(alloc: Allocator) Canvas {
    return .{
        .allocator = alloc,
    };
}

pub fn deinit(self: *Canvas) void {
    self.state.deinit(self.allocator);
    self.selected.deinit(self.allocator);

    while (self.history.buf.pop()) |*hist_state| {
        hist_state.deinit(self.allocator);
    }

    self.* = undefined;
}

pub fn addPath(self: *Canvas, tag: Path.Tag, points: []Vec2, width: Path.Width) !void {
    self.saveState();

    switch (tag) {
        .lines,
        .rect => {
            const path = Path.init(points, tag, width);
            try self.state.paths.append(self.allocator, path);
        },

        .bezier => {
            const res = try Path.Bezier.init(self.allocator, points, self.state.beziers.len, width);
            try self.state.paths.append(self.allocator, res.path);
            try self.state.beziers.append(self.allocator, res.bezier);
        },
    }
}

pub fn deleteSelectedPaths(self: *Canvas) void {
    self.saveState();

    // We will be using `swapRemove` to remove items from the paths
    // list. This changes the index of the last element. Go through
    // the indices from last to first so that this wont be an issue.
    std.sort.sort(u32, self.selected.items, {}, comptime std.sort.desc(u32));

    for (self.selected.items) |sel| {
        // Free path
        var p = self.state.paths.get(sel);
        p.deinit(self.allocator);

        // Remove from list
        self.state.paths.swapRemove(sel);
    }

    self.selected.clearRetainingCapacity();
}

pub fn clearPaths(self: *Canvas) void {
    self.saveState();

    self.state.clear(self.allocator);

    // The selection indices are not relevant anymore.
    self.selected.clearRetainingCapacity();
}

pub fn selectPath(self: *Canvas, path_index: usize) void {
    // Skip if already selected
    for (self.selected.items) |selected| {
        if (path_index == selected)
            return;
    }
    std.debug.assert(path_index < self.state.paths.len);

    self.selected.append(self.allocator, @intCast(u32, path_index)) catch unreachable;
}

pub fn translatePath(self: *Canvas, path_index: usize, translation: Vec2) void {
    self.saveState();

    var path = self.state.paths.get(path_index);
    path.translate(translation);
    self.state.paths.set(path_index, path);
}

/// Saves the current state to the history list. Calling this function also
/// flags the history as outdated, which makes sure that `undo` will save
/// the state before the next undo action.
// TODO: Temp public
pub fn saveState(self: *Canvas) void {
    // Set the new startpoint of the ring buffer to the current history
    // index. This is done so that you cannot redo something after adding a
    // new path.
    self.history.buf.setRelStart(@intCast(isize, self.history.index));

    // Only add the current state if we are not already using a previous
    // state.
    if (self.history.outdated) {
        // Make a copy of the current state
        var current_state = self.state.dupe(self.allocator) catch unreachable;

        // Add the current state to the history buffer. If the buffer is full,
        // replace the first item.
        // If a previous entry is overwritten, free the corresponding memory.
        if (self.history.buf.pushFront(current_state)) |*state_to_free| {
            state_to_free.deinit(self.allocator);
        }
    }

    // Reset history index. Essentially invalidating 'newer' (not redone)
    // entries.
    self.history.index = 0;

    // Flag next undo to save the state before undoing (it __should__
    // be a new unknown state)
    self.history.outdated = true;
}

pub fn undo(self: *Canvas) void {
    // Check if the current state is already in the history buffer. If it is
    // not, save the current state. (This is without invalidating newer entries,
    // so that we can still redo)
    if (self.history.outdated) {
        self.history.outdated = false;

        var current_state = self.state.dupe(self.allocator) catch unreachable;
        if (self.history.buf.pushFront(current_state)) |*state_to_free| {
            state_to_free.deinit(self.allocator);
        }
    }

    // Make sure that we stay inside the buffer bounds
    if (self.history.index >= self.history.buf.len()-1)
        return;

    self.history.index += 1;

    if (self.history.buf.get(self.history.index)) |hist| {
        self.state.deinit(self.allocator);
        self.state = hist.dupe(self.allocator) catch unreachable;
    } else {
        log.err("Could not get the proper history index..? index = {}",
            .{self.history.index});
    }
}

pub fn redo(self: *Canvas) void {
    // Make sure that we can redo something.
    if (self.history.index == 0)
        return;

    self.history.index -= 1;

    if (self.history.buf.get(self.history.index)) |hist| {
        self.state.deinit(self.allocator);
        self.state = hist.dupe(self.allocator) catch unreachable;
    } else {
        log.err("Could not get the proper history index..? index = {}",
            .{self.history.index});
    }
}
