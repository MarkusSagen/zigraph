//! Sequence diagram layout algorithm.
//!
//! Places actors left-to-right, messages top-to-bottom.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Sequence = model.Sequence;

pub const SequenceLayout = struct {
    actor_positions: []f64, // x center per actor
    message_ys: []f64, // y per message
    total_width: f64,
    total_height: f64,
    allocator: Allocator,

    pub fn deinit(self: *SequenceLayout) void {
        self.allocator.free(self.actor_positions);
        self.allocator.free(self.message_ys);
    }
};

pub const LayoutConfig = struct {
    actor_spacing: f64 = 120,
    message_spacing: f64 = 40,
    header_height: f64 = 50,
    margin: f64 = 20,
    actor_box_width: f64 = 80,
    actor_box_height: f64 = 30,
};

pub fn layoutSequence(seq: *const Sequence, allocator: Allocator, config: LayoutConfig) !SequenceLayout {
    const n_actors = seq.actors.items.len;
    const n_msgs = seq.messages.items.len;

    var positions = try allocator.alloc(f64, n_actors);
    errdefer allocator.free(positions);

    var msg_ys = try allocator.alloc(f64, n_msgs);
    errdefer allocator.free(msg_ys);

    // Actors placed left-to-right
    for (0..n_actors) |i| {
        const fi: f64 = @floatFromInt(i);
        positions[i] = config.margin + fi * config.actor_spacing + config.actor_box_width / 2;
    }

    // Messages placed top-to-bottom after header
    for (0..n_msgs) |i| {
        const fi: f64 = @floatFromInt(i);
        msg_ys[i] = config.header_height + config.margin + fi * config.message_spacing;
    }

    const last_actor_x = if (n_actors > 0) positions[n_actors - 1] else 0;
    const last_msg_y = if (n_msgs > 0) msg_ys[n_msgs - 1] else config.header_height;

    return .{
        .actor_positions = positions,
        .message_ys = msg_ys,
        .total_width = last_actor_x + config.actor_box_width / 2 + config.margin,
        .total_height = last_msg_y + config.message_spacing + config.margin,
        .allocator = allocator,
    };
}

test "sequence layout: actor positions" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    _ = try seq.addActor("A", .{});
    _ = try seq.addActor("B", .{});
    _ = try seq.addActor("C", .{});

    var result = try layoutSequence(&seq, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.actor_positions[1] > result.actor_positions[0]);
    try std.testing.expect(result.actor_positions[2] > result.actor_positions[1]);
    const gap1 = result.actor_positions[1] - result.actor_positions[0];
    const gap2 = result.actor_positions[2] - result.actor_positions[1];
    try std.testing.expectApproxEqAbs(gap1, gap2, 0.01);
}

test "sequence layout: message y positions" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("A", .{});
    const b = try seq.addActor("B", .{});
    _ = try seq.addMessage(a, b, "m1", .{});
    _ = try seq.addMessage(b, a, "m2", .{});

    var result = try layoutSequence(&seq, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.message_ys[1] > result.message_ys[0]);
}
