//! Mindmap radial tree layout.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Mindmap = model.Mindmap;

pub const MindmapLayout = struct {
    positions: []Position,
    total_width: f64,
    total_height: f64,
    allocator: Allocator,

    pub const Position = struct { x: f64, y: f64 };

    pub fn deinit(self: *MindmapLayout) void {
        self.allocator.free(self.positions);
    }
};

pub const LayoutConfig = struct {
    ring_spacing: f64 = 100,
    node_width: f64 = 80,
    node_height: f64 = 30,
};

pub fn layoutMindmap(mm: *const Mindmap, allocator: Allocator, config: LayoutConfig) !MindmapLayout {
    const n = mm.nodes.items.len;
    var positions = try allocator.alloc(MindmapLayout.Position, n);
    errdefer allocator.free(positions);

    if (n == 0 or mm.root == null) {
        return .{ .positions = positions, .total_width = 0, .total_height = 0, .allocator = allocator };
    }

    // Root at center
    const cx: f64 = 300;
    const cy: f64 = 300;
    positions[mm.root.?] = .{ .x = cx, .y = cy };

    // BFS layout: each level at increasing radius
    // Using managed ArrayList for local temporary is fine
    var queue = std.ArrayList(struct { id: usize, depth: u32, angle_start: f64, angle_end: f64 }).init(allocator);
    defer queue.deinit();

    try queue.append(.{ .id = mm.root.?, .depth = 0, .angle_start = 0, .angle_end = std.math.tau });

    var max_r: f64 = 0;
    var qi: usize = 0;
    while (qi < queue.items.len) : (qi += 1) {
        const item = queue.items[qi];
        const node = mm.nodes.items[item.id];
        const n_children = node.children.items.len;
        if (n_children == 0) continue;

        const angle_span = item.angle_end - item.angle_start;
        const child_depth = item.depth + 1;
        const radius: f64 = @as(f64, @floatFromInt(child_depth)) * config.ring_spacing;
        if (radius > max_r) max_r = radius;

        for (node.children.items, 0..) |child_id, ci| {
            const ci_f: f64 = @floatFromInt(ci);
            const n_f: f64 = @floatFromInt(n_children);
            const child_angle_start = item.angle_start + angle_span * ci_f / n_f;
            const child_angle_end = item.angle_start + angle_span * (ci_f + 1) / n_f;
            const mid_angle = (child_angle_start + child_angle_end) / 2;

            positions[child_id] = .{
                .x = cx + radius * @cos(mid_angle),
                .y = cy + radius * @sin(mid_angle),
            };

            try queue.append(.{
                .id = child_id,
                .depth = child_depth,
                .angle_start = child_angle_start,
                .angle_end = child_angle_end,
            });
        }
    }

    const size = (max_r + config.node_width) * 2 + 40;

    return .{
        .positions = positions,
        .total_width = @max(size, cx * 2 + 40),
        .total_height = @max(size, cy * 2 + 40),
        .allocator = allocator,
    };
}

test "mindmap layout: root at center" {
    const allocator = std.testing.allocator;
    var mm = Mindmap.init(allocator);
    defer mm.deinit();

    const root = try mm.addNode("Root", .{});
    mm.setRoot(root);
    const c1 = try mm.addNode("A", .{});
    try mm.addChild(root, c1);

    var result = try layoutMindmap(&mm, allocator, .{});
    defer result.deinit();

    // Root should be roughly at center
    try std.testing.expectApproxEqAbs(@as(f64, 300), result.positions[0].x, 1);
    // Child should be offset from root
    try std.testing.expect(@abs(result.positions[1].x - result.positions[0].x) > 10);
}
