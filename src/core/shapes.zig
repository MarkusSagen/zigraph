//! Shape vertex generation for node rendering.
//!
//! Given a NodeShape, center point, width, and height, produces polygon
//! vertices or circle/ellipse parameters for rendering.
//!
//! Used by:
//! - SVG renderer: actual geometric shapes via <polygon>, <circle>, etc.
//! - DrawingIR conversion: LayoutNode shape → appropriate DrawingPrimitive
//! - Terminal renderer: approximation with box-drawing characters

const std = @import("std");
const graph_mod = @import("graph.zig");
const NodeShape = graph_mod.NodeShape;

/// A 2D point for shape vertices.
pub const ShapePoint = struct {
    x: f64,
    y: f64,
};

/// Result of shape generation — either polygon vertices or ellipse params.
pub const ShapeResult = union(enum) {
    /// Polygon defined by ordered vertices (first == last to close)
    polygon: []const ShapePoint,
    /// Circle defined by center + radius
    circle_shape: struct { cx: f64, cy: f64, radius: f64 },
    /// Ellipse defined by center + radii
    ellipse_shape: struct { cx: f64, cy: f64, rx: f64, ry: f64 },
    /// Rectangle (possibly with corner_radius for rounded_rect)
    rect_shape: struct { x: f64, y: f64, width: f64, height: f64, corner_radius: f64 },
};

/// Generate shape geometry for the given node shape.
///
/// For polygon shapes, vertices are returned in a caller-provided buffer.
/// Buffer must have at least `maxVertices(shape)` capacity.
///
/// Returns a ShapeResult describing the geometry.
pub fn generateShape(
    shape: NodeShape,
    center_x: f64,
    center_y: f64,
    width: f64,
    height: f64,
    vertex_buf: []ShapePoint,
) ShapeResult {
    const hw = width / 2.0;
    const hh = height / 2.0;
    const cx = center_x;
    const cy = center_y;

    return switch (shape) {
        .rect => .{ .rect_shape = .{
            .x = cx - hw,
            .y = cy - hh,
            .width = width,
            .height = height,
            .corner_radius = 0,
        } },
        .rounded_rect => .{ .rect_shape = .{
            .x = cx - hw,
            .y = cy - hh,
            .width = width,
            .height = height,
            .corner_radius = @min(hw, hh) * 0.3,
        } },
        .circle => .{ .circle_shape = .{
            .cx = cx,
            .cy = cy,
            .radius = @max(hw, hh),
        } },
        .double_circle => .{ .circle_shape = .{
            .cx = cx,
            .cy = cy,
            .radius = @max(hw, hh),
        } },
        .stadium => .{ .rect_shape = .{
            .x = cx - hw,
            .y = cy - hh,
            .width = width,
            .height = height,
            .corner_radius = hh, // fully rounded ends
        } },
        .diamond => blk: {
            // 4 vertices: top, right, bottom, left
            vertex_buf[0] = .{ .x = cx, .y = cy - hh }; // top
            vertex_buf[1] = .{ .x = cx + hw, .y = cy }; // right
            vertex_buf[2] = .{ .x = cx, .y = cy + hh }; // bottom
            vertex_buf[3] = .{ .x = cx - hw, .y = cy }; // left
            vertex_buf[4] = vertex_buf[0]; // close
            break :blk .{ .polygon = vertex_buf[0..5] };
        },
        .hexagon => blk: {
            // 6 vertices: flat-top hexagon
            const inset = hw * 0.25;
            vertex_buf[0] = .{ .x = cx - hw + inset, .y = cy - hh }; // top-left
            vertex_buf[1] = .{ .x = cx + hw - inset, .y = cy - hh }; // top-right
            vertex_buf[2] = .{ .x = cx + hw, .y = cy }; // right
            vertex_buf[3] = .{ .x = cx + hw - inset, .y = cy + hh }; // bottom-right
            vertex_buf[4] = .{ .x = cx - hw + inset, .y = cy + hh }; // bottom-left
            vertex_buf[5] = .{ .x = cx - hw, .y = cy }; // left
            vertex_buf[6] = vertex_buf[0]; // close
            break :blk .{ .polygon = vertex_buf[0..7] };
        },
        .trapezoid => blk: {
            // 4 vertices: wider at bottom, narrower at top
            const inset = hw * 0.2;
            vertex_buf[0] = .{ .x = cx - hw + inset, .y = cy - hh }; // top-left
            vertex_buf[1] = .{ .x = cx + hw - inset, .y = cy - hh }; // top-right
            vertex_buf[2] = .{ .x = cx + hw, .y = cy + hh }; // bottom-right
            vertex_buf[3] = .{ .x = cx - hw, .y = cy + hh }; // bottom-left
            vertex_buf[4] = vertex_buf[0]; // close
            break :blk .{ .polygon = vertex_buf[0..5] };
        },
        .parallelogram => blk: {
            // 4 vertices: slanted rectangle
            const skew = hw * 0.25;
            vertex_buf[0] = .{ .x = cx - hw + skew, .y = cy - hh };
            vertex_buf[1] = .{ .x = cx + hw + skew, .y = cy - hh };
            vertex_buf[2] = .{ .x = cx + hw - skew, .y = cy + hh };
            vertex_buf[3] = .{ .x = cx - hw - skew, .y = cy + hh };
            vertex_buf[4] = vertex_buf[0]; // close
            break :blk .{ .polygon = vertex_buf[0..5] };
        },
        .cylinder => .{ .rect_shape = .{
            .x = cx - hw,
            .y = cy - hh,
            .width = width,
            .height = height,
            .corner_radius = 0,
        } },
        .subroutine => .{ .rect_shape = .{
            .x = cx - hw,
            .y = cy - hh,
            .width = width,
            .height = height,
            .corner_radius = 0,
        } },
        .asymmetric => blk: {
            // Flag/pennant shape: > label ]
            vertex_buf[0] = .{ .x = cx - hw, .y = cy - hh }; // top-left
            vertex_buf[1] = .{ .x = cx + hw * 0.6, .y = cy - hh }; // top-right indent
            vertex_buf[2] = .{ .x = cx + hw, .y = cy }; // right point
            vertex_buf[3] = .{ .x = cx + hw * 0.6, .y = cy + hh }; // bottom-right indent
            vertex_buf[4] = .{ .x = cx - hw, .y = cy + hh }; // bottom-left
            vertex_buf[5] = vertex_buf[0]; // close
            break :blk .{ .polygon = vertex_buf[0..6] };
        },
    };
}

/// Maximum number of vertices any shape can produce (hexagon = 6 + 1 close).
pub fn maxVertices(shape: NodeShape) usize {
    return switch (shape) {
        .diamond, .trapezoid, .parallelogram => 5, // 4 + close
        .hexagon => 7, // 6 + close
        .asymmetric => 6, // 5 + close
        else => 0, // non-polygon shapes
    };
}

// ============================================================================
// Tests
// ============================================================================

test "shapes: rect returns rect_shape" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.rect, 50, 25, 100, 50, &buf);
    try std.testing.expect(result == .rect_shape);
    try std.testing.expect(result.rect_shape.x == 0);
    try std.testing.expect(result.rect_shape.y == 0);
    try std.testing.expect(result.rect_shape.width == 100);
    try std.testing.expect(result.rect_shape.height == 50);
    try std.testing.expect(result.rect_shape.corner_radius == 0);
}

test "shapes: rounded_rect has non-zero corner radius" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.rounded_rect, 50, 25, 100, 50, &buf);
    try std.testing.expect(result == .rect_shape);
    try std.testing.expect(result.rect_shape.corner_radius > 0);
}

test "shapes: circle returns circle_shape" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.circle, 100, 100, 60, 40, &buf);
    try std.testing.expect(result == .circle_shape);
    try std.testing.expect(result.circle_shape.cx == 100);
    try std.testing.expect(result.circle_shape.cy == 100);
    // Radius is max(hw, hh) = max(30, 20) = 30
    try std.testing.expect(result.circle_shape.radius == 30);
}

test "shapes: diamond produces 5 vertices (4 + close)" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.diamond, 50, 50, 80, 60, &buf);
    try std.testing.expect(result == .polygon);
    try std.testing.expectEqual(@as(usize, 5), result.polygon.len);

    // Top vertex: (50, 20) — center_y - height/2
    try std.testing.expect(result.polygon[0].x == 50);
    try std.testing.expect(result.polygon[0].y == 20);
    // Right vertex: (90, 50) — center_x + width/2
    try std.testing.expect(result.polygon[1].x == 90);
    try std.testing.expect(result.polygon[1].y == 50);
    // Bottom vertex: (50, 80)
    try std.testing.expect(result.polygon[2].x == 50);
    try std.testing.expect(result.polygon[2].y == 80);
    // Left vertex: (10, 50)
    try std.testing.expect(result.polygon[3].x == 10);
    try std.testing.expect(result.polygon[3].y == 50);
    // Closed: last == first
    try std.testing.expect(result.polygon[4].x == result.polygon[0].x);
    try std.testing.expect(result.polygon[4].y == result.polygon[0].y);
}

test "shapes: hexagon produces 7 vertices (6 + close)" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.hexagon, 50, 50, 100, 60, &buf);
    try std.testing.expect(result == .polygon);
    try std.testing.expectEqual(@as(usize, 7), result.polygon.len);

    // Verify it closes
    try std.testing.expect(result.polygon[6].x == result.polygon[0].x);
    try std.testing.expect(result.polygon[6].y == result.polygon[0].y);

    // Right vertex should be at center_x + hw
    try std.testing.expect(result.polygon[2].x == 100); // cx + hw = 50 + 50
    try std.testing.expect(result.polygon[2].y == 50); // at center height
}

test "shapes: trapezoid produces 5 vertices (4 + close)" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.trapezoid, 50, 50, 100, 60, &buf);
    try std.testing.expect(result == .polygon);
    try std.testing.expectEqual(@as(usize, 5), result.polygon.len);

    // Bottom is wider than top
    const top_width = result.polygon[1].x - result.polygon[0].x;
    const bottom_width = result.polygon[2].x - result.polygon[3].x;
    try std.testing.expect(bottom_width > top_width);
}

test "shapes: parallelogram produces 5 vertices (4 + close)" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.parallelogram, 50, 50, 100, 60, &buf);
    try std.testing.expect(result == .polygon);
    try std.testing.expectEqual(@as(usize, 5), result.polygon.len);

    // Top edge is shifted right relative to bottom edge (skew)
    try std.testing.expect(result.polygon[0].x > result.polygon[3].x);
}

test "shapes: stadium has corner_radius equal to half height" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.stadium, 50, 25, 100, 40, &buf);
    try std.testing.expect(result == .rect_shape);
    // corner_radius = hh = 20
    try std.testing.expect(result.rect_shape.corner_radius == 20);
}

test "shapes: asymmetric produces flag shape (6 vertices)" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.asymmetric, 50, 50, 80, 40, &buf);
    try std.testing.expect(result == .polygon);
    try std.testing.expectEqual(@as(usize, 6), result.polygon.len);

    // Right point extends to center_x + hw
    try std.testing.expect(result.polygon[2].x == 90); // cx + hw = 50 + 40
    try std.testing.expect(result.polygon[2].y == 50); // at center
}

test "shapes: maxVertices correct for all shapes" {
    try std.testing.expectEqual(@as(usize, 5), maxVertices(.diamond));
    try std.testing.expectEqual(@as(usize, 7), maxVertices(.hexagon));
    try std.testing.expectEqual(@as(usize, 5), maxVertices(.trapezoid));
    try std.testing.expectEqual(@as(usize, 5), maxVertices(.parallelogram));
    try std.testing.expectEqual(@as(usize, 6), maxVertices(.asymmetric));
    try std.testing.expectEqual(@as(usize, 0), maxVertices(.rect));
    try std.testing.expectEqual(@as(usize, 0), maxVertices(.circle));
}

test "shapes: double_circle returns circle_shape" {
    var buf: [8]ShapePoint = undefined;
    const result = generateShape(.double_circle, 50, 50, 40, 40, &buf);
    try std.testing.expect(result == .circle_shape);
    try std.testing.expect(result.circle_shape.radius == 20);
}
