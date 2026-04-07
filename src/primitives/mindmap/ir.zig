//! MindmapIR → DrawingIR conversion.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Mindmap = model.Mindmap;
const layout_mod = @import("layout.zig");
const layoutMindmap = layout_mod.layoutMindmap;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

pub fn toDrawing(mm: *const Mindmap, allocator: Allocator, config: LayoutConfig) !Drawing {
    var ml = try layoutMindmap(mm, allocator, config);
    defer ml.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(ml.total_width, ml.total_height);

    const nw = config.node_width;
    const nh = config.node_height;

    // Draw edges first (parent → child lines)
    for (mm.nodes.items) |node| {
        if (node.parent) |pid| {
            const px = ml.positions[pid].x;
            const py = ml.positions[pid].y;
            const cx = ml.positions[node.id].x;
            const cy = ml.positions[node.id].y;
            try d.addPrimitive(.{ .line = .{
                .x1 = px,
                .y1 = py,
                .x2 = cx,
                .y2 = cy,
            } });
        }
    }

    // Draw nodes
    for (mm.nodes.items) |node| {
        const x = ml.positions[node.id].x;
        const y = ml.positions[node.id].y;

        const is_root = mm.root != null and node.id == mm.root.?;
        const w = if (is_root) nw * 1.2 else nw;
        const h = if (is_root) nh * 1.2 else nh;

        try d.addPrimitive(.{ .rect = .{
            .x = x - w / 2,
            .y = y - h / 2,
            .width = w,
            .height = h,
            .corner_radius = 8,
        } });
        try d.addPrimitive(.{ .text = .{
            .x = x,
            .y = y,
            .content = node.text,
            .alignment = .center,
            .style = if (is_root) .{ .bold = true } else .{},
        } });
    }

    return d;
}

test "mindmap ir: basic tree to drawing" {
    const allocator = std.testing.allocator;
    var mm = Mindmap.init(allocator);
    defer mm.deinit();

    const root = try mm.addNode("Center", .{});
    mm.setRoot(root);
    const c1 = try mm.addNode("A", .{});
    try mm.addChild(root, c1);

    var d = try toDrawing(&mm, allocator, .{});
    defer d.deinit();

    // 1 edge line + 2 nodes (rect+text each) = 5 primitives
    try std.testing.expect(d.primitives.items.len >= 5);
}
