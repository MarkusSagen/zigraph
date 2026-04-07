//! LayoutIR → DrawingIR conversion.
//!
//! Converts graph layout results into renderer-agnostic drawing primitives:
//! - Each LayoutNode → Rect + Text (label centered inside)
//! - Each LayoutEdge → Path with appropriate markers
//! - Each SubgraphInfo → Group with border + label Text

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const drawing = @import("ir.zig");
const DrawingPrimitive = drawing.DrawingPrimitive;
const Drawing = drawing.Drawing;
const Point = drawing.Point;

/// Convert a LayoutIR(usize) into a Drawing.
/// Caller owns the returned Drawing and must call deinit().
pub fn convertLayoutIR(layout_ir: *const ir_mod.LayoutIR(usize), allocator: Allocator) !Drawing {
    var result = Drawing.init(allocator);
    errdefer result.deinit();

    // Convert nodes: each becomes a Rect + Text
    for (layout_ir.getNodes()) |node| {
        if (node.kind == .dummy) continue;

        // Node rectangle
        try result.addPrimitive(.{ .rect = .{
            .x = @floatFromInt(node.x),
            .y = @floatFromInt(node.y),
            .width = @floatFromInt(node.width),
            .height = @floatFromInt(node.height),
            .border_style = .solid,
        } });

        // Node label (centered inside the rect)
        if (node.label.len > 0) {
            try result.addPrimitive(.{ .text = .{
                .x = @floatFromInt(node.center_x),
                .y = @as(f64, @floatFromInt(node.y)) + @as(f64, @floatFromInt(node.height)) / 2.0,
                .content = node.label,
                .alignment = .center,
            } });
        }
    }

    // Convert edges: each becomes a Path (or Line for direct edges)
    for (layout_ir.getEdges()) |edge| {
        switch (edge.path) {
            .direct => {
                try result.addPrimitive(.{ .line = .{
                    .x1 = @floatFromInt(edge.from_x),
                    .y1 = @floatFromInt(edge.from_y),
                    .x2 = @floatFromInt(edge.to_x),
                    .y2 = @floatFromInt(edge.to_y),
                    .end_marker = if (edge.directed) .arrow else .none,
                    .style = if (edge.reversed) .dashed else .solid,
                } });
            },
            .corner => |c| {
                const pts = [_]Point{
                    .{ .x = @floatFromInt(edge.from_x), .y = @floatFromInt(edge.from_y) },
                    .{ .x = @floatFromInt(edge.from_x), .y = @floatFromInt(c.horizontal_y) },
                    .{ .x = @floatFromInt(edge.to_x), .y = @floatFromInt(c.horizontal_y) },
                    .{ .x = @floatFromInt(edge.to_x), .y = @floatFromInt(edge.to_y) },
                };
                try result.addPrimitive(.{ .path = .{
                    .points = &pts,
                    .end_marker = if (edge.directed) .arrow else .none,
                    .style = if (edge.reversed) .dashed else .solid,
                } });
            },
            .multi_segment => |ms| {
                // Build point list: from → waypoints → to
                var pts = std.ArrayList(Point).init(allocator);
                defer pts.deinit();

                try pts.append(.{
                    .x = @floatFromInt(edge.from_x),
                    .y = @floatFromInt(edge.from_y),
                });
                for (ms.waypoints.items) |wp| {
                    try pts.append(.{
                        .x = @floatFromInt(wp.x),
                        .y = @floatFromInt(wp.y),
                    });
                }
                try pts.append(.{
                    .x = @floatFromInt(edge.to_x),
                    .y = @floatFromInt(edge.to_y),
                });

                // Allocate owned slice for the Drawing to reference
                const owned_pts = try allocator.dupe(Point, pts.items);
                try result.addPrimitive(.{ .path = .{
                    .points = owned_pts,
                    .end_marker = if (edge.directed) .arrow else .none,
                    .style = if (edge.reversed) .dashed else .solid,
                } });
            },
            .spline => |sp| {
                const pts = [_]Point{
                    .{ .x = @floatFromInt(edge.from_x), .y = @floatFromInt(edge.from_y) },
                    .{ .x = @floatFromInt(sp.cp1_x), .y = @floatFromInt(sp.cp1_y) },
                    .{ .x = @floatFromInt(sp.cp2_x), .y = @floatFromInt(sp.cp2_y) },
                    .{ .x = @floatFromInt(edge.to_x), .y = @floatFromInt(edge.to_y) },
                };
                try result.addPrimitive(.{ .path = .{
                    .points = &pts,
                    .is_spline = true,
                    .end_marker = if (edge.directed) .arrow else .none,
                } });
            },
            .side_channel => |sc| {
                const pts = [_]Point{
                    .{ .x = @floatFromInt(edge.from_x), .y = @floatFromInt(edge.from_y) },
                    .{ .x = @floatFromInt(sc.channel_x), .y = @floatFromInt(sc.start_y) },
                    .{ .x = @floatFromInt(sc.channel_x), .y = @floatFromInt(sc.end_y) },
                    .{ .x = @floatFromInt(edge.to_x), .y = @floatFromInt(edge.to_y) },
                };
                try result.addPrimitive(.{ .path = .{
                    .points = &pts,
                    .end_marker = if (edge.directed) .arrow else .none,
                } });
            },
            .bus => {
                // Bus edges are rendered as shared horizontal lines;
                // for DrawingIR, emit a simple line from source to target
                try result.addPrimitive(.{ .line = .{
                    .x1 = @floatFromInt(edge.from_x),
                    .y1 = @floatFromInt(edge.from_y),
                    .x2 = @floatFromInt(edge.to_x),
                    .y2 = @floatFromInt(edge.to_y),
                    .end_marker = if (edge.directed) .arrow else .none,
                } });
            },
        }

        // Edge label
        if (edge.label) |label_text| {
            try result.addPrimitive(.{ .text = .{
                .x = @floatFromInt(edge.label_x),
                .y = @floatFromInt(edge.label_y),
                .content = label_text,
                .alignment = .center,
                .style = .{ .dim = true },
            } });
        }
    }

    // Convert subgraphs: each becomes a Group
    for (layout_ir.getSubgraphs()) |sg| {
        // Group border + label
        const label_prim = [_]DrawingPrimitive{
            .{ .rect = .{
                .x = @floatFromInt(sg.x),
                .y = @floatFromInt(sg.y),
                .width = @floatFromInt(sg.width),
                .height = @floatFromInt(sg.height),
                .border_style = .dashed,
            } },
            .{ .text = .{
                .x = @as(f64, @floatFromInt(sg.x)) + 4,
                .y = @as(f64, @floatFromInt(sg.y)) + 1,
                .content = sg.label,
                .alignment = .left,
                .style = .{ .bold = true },
            } },
        };
        try result.addPrimitive(.{ .group = .{
            .children = &label_prim,
            .label = sg.label,
            .border_style = .dashed,
            .x = @floatFromInt(sg.x),
            .y = @floatFromInt(sg.y),
            .width = @floatFromInt(sg.width),
            .height = @floatFromInt(sg.height),
        } });
    }

    // Set drawing dimensions from layout
    result.setDimensions(@floatFromInt(layout_ir.width), @floatFromInt(layout_ir.height));

    return result;
}

// ============================================================================
// Tests
// ============================================================================

const TestLayoutIR = ir_mod.LayoutIR(usize);

test "convert: single node produces rect + text" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "Start",
        .x = 10,
        .y = 5,
        .width = 7,
        .height = 1,
        .center_x = 13,
        .center_y = 5,
        .level = 0,
        .level_position = 0,
    });
    layout_ir.setDimensions(80, 24);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    // Expect 2 primitives: rect + text
    try std.testing.expectEqual(@as(usize, 2), drawing_result.primitives.items.len);
    try std.testing.expect(drawing_result.primitives.items[0] == .rect);
    try std.testing.expect(drawing_result.primitives.items[1] == .text);

    // Verify rect position
    const rect = drawing_result.primitives.items[0].rect;
    try std.testing.expect(rect.x == 10);
    try std.testing.expect(rect.y == 5);
    try std.testing.expect(rect.width == 7);

    // Verify text content
    const text = drawing_result.primitives.items[1].text;
    try std.testing.expectEqualStrings("Start", text.content);
    try std.testing.expect(text.x == 13);

    // Verify dimensions
    try std.testing.expect(drawing_result.width == 80);
    try std.testing.expect(drawing_result.height == 24);
}

test "convert: dummy nodes are skipped" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "Real",
        .x = 0,
        .y = 0,
        .width = 6,
        .height = 1,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });
    try layout_ir.addNode(.{
        .id = 999,
        .label = "",
        .x = 0,
        .y = 2,
        .width = 1,
        .height = 1,
        .center_x = 0,
        .level = 1,
        .level_position = 0,
        .kind = .dummy,
    });
    layout_ir.setDimensions(40, 10);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    // Only 2 primitives (rect + text for the real node), dummy is skipped
    try std.testing.expectEqual(@as(usize, 2), drawing_result.primitives.items.len);
}

test "convert: direct edge produces line with arrow" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 10,
        .from_y = 5,
        .to_x = 10,
        .to_y = 10,
        .path = .{ .direct = {} },
        .edge_index = 0,
        .directed = true,
    });
    layout_ir.setDimensions(40, 20);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    try std.testing.expectEqual(@as(usize, 1), drawing_result.primitives.items.len);
    try std.testing.expect(drawing_result.primitives.items[0] == .line);

    const line = drawing_result.primitives.items[0].line;
    try std.testing.expect(line.end_marker == .arrow);
    try std.testing.expect(line.style == .solid);
}

test "convert: reversed edge produces dashed line" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 10,
        .from_y = 5,
        .to_x = 10,
        .to_y = 10,
        .path = .{ .direct = {} },
        .edge_index = 0,
        .directed = true,
        .reversed = true,
    });
    layout_ir.setDimensions(40, 20);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    const line = drawing_result.primitives.items[0].line;
    try std.testing.expect(line.style == .dashed);
}

test "convert: undirected edge has no arrow" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 5,
        .from_y = 0,
        .to_x = 15,
        .to_y = 0,
        .path = .{ .direct = {} },
        .edge_index = 0,
        .directed = false,
    });
    layout_ir.setDimensions(40, 10);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    const line = drawing_result.primitives.items[0].line;
    try std.testing.expect(line.end_marker == .none);
}

test "convert: corner edge produces path with 4 points" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 10,
        .from_y = 5,
        .to_x = 30,
        .to_y = 15,
        .path = .{ .corner = .{ .horizontal_y = 10 } },
        .edge_index = 0,
    });
    layout_ir.setDimensions(40, 20);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    try std.testing.expect(drawing_result.primitives.items[0] == .path);
    const path = drawing_result.primitives.items[0].path;
    try std.testing.expectEqual(@as(usize, 4), path.points.len);
    try std.testing.expect(path.end_marker == .arrow);
}

test "convert: edge with label produces text primitive" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 10,
        .from_y = 5,
        .to_x = 10,
        .to_y = 15,
        .path = .{ .direct = {} },
        .edge_index = 0,
        .label = "depends on",
        .label_x = 10,
        .label_y = 10,
    });
    layout_ir.setDimensions(40, 20);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    // line + label text = 2 primitives
    try std.testing.expectEqual(@as(usize, 2), drawing_result.primitives.items.len);
    try std.testing.expect(drawing_result.primitives.items[1] == .text);
    try std.testing.expectEqualStrings("depends on", drawing_result.primitives.items[1].text.content);
}

test "convert: subgraph produces group primitive" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.subgraphs.append(allocator, .{
        .id = 1,
        .parent_id = null,
        .label = "Cluster A",
        .x = 5,
        .y = 2,
        .width = 30,
        .height = 15,
    });
    layout_ir.setDimensions(40, 20);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    try std.testing.expectEqual(@as(usize, 1), drawing_result.primitives.items.len);
    try std.testing.expect(drawing_result.primitives.items[0] == .group);

    const group = drawing_result.primitives.items[0].group;
    try std.testing.expectEqualStrings("Cluster A", group.label.?);
    try std.testing.expect(group.border_style == .dashed);
}

test "convert: node with empty label skips text" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "",
        .x = 0,
        .y = 0,
        .width = 2,
        .height = 1,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    layout_ir.setDimensions(10, 5);

    var drawing_result = try convertLayoutIR(&layout_ir, allocator);
    defer drawing_result.deinit();

    // Only rect, no text for empty label
    try std.testing.expectEqual(@as(usize, 1), drawing_result.primitives.items.len);
    try std.testing.expect(drawing_result.primitives.items[0] == .rect);
}
