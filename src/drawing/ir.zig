//! Drawing Intermediate Representation — renderer-agnostic drawing primitives.
//!
//! This is the shared IR consumed by all renderers (terminal, SVG, JSON).
//! Every diagram type (graph, sequence, gantt, etc.) converts its layout
//! output into DrawingIR before rendering.
//!
//! ## Primitives
//!
//! Rect, Circle, Ellipse, Arc, Polygon, Line, Path, Text, Group
//!
//! ## Usage
//!
//! ```zig
//! const drawing = @import("drawing/ir.zig");
//! var primitives = std.ArrayList(drawing.DrawingPrimitive).init(allocator);
//! try primitives.append(.{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 50 } });
//! try primitives.append(.{ .text = .{ .x = 50, .y = 25, .content = "Hello" } });
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Coordinate and style types
// ============================================================================

/// A 2D point in drawing space.
pub const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

/// Border/line style for shapes and connectors.
pub const BorderStyle = enum {
    solid,
    dashed,
    dotted,
    double,
    bold,
    none,
};

/// Fill specification for shapes.
pub const Fill = union(enum) {
    none: void,
    solid: Color,
    gradient: struct {
        start_color: Color,
        end_color: Color,
        direction: GradientDirection,
    },

    pub const GradientDirection = enum { horizontal, vertical, diagonal };
};

/// RGB color.
pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

/// Text styling flags (composable).
pub const TextStyle = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    _padding: u4 = 0,
};

/// Text alignment within a bounding box.
pub const TextAlignment = enum {
    left,
    center,
    right,
};

/// Marker types for line/path endpoints.
pub const MarkerType = enum {
    none,
    arrow,
    hollow_arrow,
    diamond,
    hollow_diamond,
    circle,
    crow_foot_one,
    crow_foot_many,
    crow_foot_zero_one,
    crow_foot_zero_many,
};

// ============================================================================
// Drawing primitives
// ============================================================================

/// Rectangle with optional rounded corners.
pub const Rect = struct {
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 0,
    height: f64 = 0,
    corner_radius: f64 = 0,
    fill: Fill = .{ .none = {} },
    border_style: BorderStyle = .solid,
    border_weight: f64 = 1,
};

/// Circle defined by center and radius.
pub const Circle = struct {
    cx: f64 = 0,
    cy: f64 = 0,
    radius: f64 = 0,
    fill: Fill = .{ .none = {} },
    border_style: BorderStyle = .solid,
};

/// Ellipse defined by center and radii.
pub const Ellipse = struct {
    cx: f64 = 0,
    cy: f64 = 0,
    rx: f64 = 0,
    ry: f64 = 0,
    fill: Fill = .{ .none = {} },
    border_style: BorderStyle = .solid,
};

/// Circular arc segment.
pub const Arc = struct {
    cx: f64 = 0,
    cy: f64 = 0,
    radius: f64 = 0,
    start_angle: f64 = 0,
    end_angle: f64 = 0,
    fill: Fill = .{ .none = {} },
    border_style: BorderStyle = .solid,
};

/// Arbitrary polygon defined by vertex list.
pub const Polygon = struct {
    points: []const Point = &.{},
    fill: Fill = .{ .none = {} },
    border_style: BorderStyle = .solid,
};

/// Simple two-point line segment.
pub const Line = struct {
    x1: f64 = 0,
    y1: f64 = 0,
    x2: f64 = 0,
    y2: f64 = 0,
    style: BorderStyle = .solid,
    weight: f64 = 1,
    start_marker: MarkerType = .none,
    end_marker: MarkerType = .none,
};

/// Multi-segment path (polyline or spline).
pub const Path = struct {
    points: []const Point = &.{},
    is_spline: bool = false,
    style: BorderStyle = .solid,
    weight: f64 = 1,
    start_marker: MarkerType = .none,
    end_marker: MarkerType = .none,
};

/// Text label at a position.
pub const Text = struct {
    x: f64 = 0,
    y: f64 = 0,
    content: []const u8 = "",
    alignment: TextAlignment = .center,
    style: TextStyle = .{},
    font_size: f64 = 14,
};

/// Group container holding child primitives.
pub const Group = struct {
    children: []const DrawingPrimitive = &.{},
    label: ?[]const u8 = null,
    border_style: BorderStyle = .none,
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 0,
    height: f64 = 0,
};

/// Tagged union of all drawing primitives.
pub const DrawingPrimitive = union(enum) {
    rect: Rect,
    circle: Circle,
    ellipse: Ellipse,
    arc: Arc,
    polygon: Polygon,
    line: Line,
    path: Path,
    text: Text,
    group: Group,
};

/// A complete drawing — the top-level output of any diagram pipeline.
pub const Drawing = struct {
    primitives: std.ArrayListUnmanaged(DrawingPrimitive),
    width: f64,
    height: f64,
    allocator: Allocator,

    pub fn init(allocator: Allocator) Drawing {
        return .{
            .primitives = .{},
            .width = 0,
            .height = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Drawing) void {
        self.primitives.deinit(self.allocator);
    }

    pub fn addPrimitive(self: *Drawing, prim: DrawingPrimitive) !void {
        try self.primitives.append(self.allocator, prim);
    }

    pub fn setDimensions(self: *Drawing, width: f64, height: f64) void {
        self.width = width;
        self.height = height;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Point: default construction" {
    const p = Point{};
    try std.testing.expectEqual(@as(f64, 0), p.x);
    try std.testing.expectEqual(@as(f64, 0), p.y);
}

test "Point: explicit values" {
    const p = Point{ .x = 10.5, .y = -3.2 };
    try std.testing.expect(p.x == 10.5);
    try std.testing.expect(p.y == -3.2);
}

test "Rect: default construction" {
    const r = Rect{};
    try std.testing.expectEqual(@as(f64, 0), r.x);
    try std.testing.expectEqual(@as(f64, 0), r.width);
    try std.testing.expectEqual(@as(f64, 0), r.corner_radius);
    try std.testing.expect(r.border_style == .solid);
    try std.testing.expect(r.fill == .none);
}

test "Rect: with dimensions and rounded corners" {
    const r = Rect{
        .x = 10,
        .y = 20,
        .width = 100,
        .height = 50,
        .corner_radius = 5,
        .border_style = .dashed,
    };
    try std.testing.expect(r.width == 100);
    try std.testing.expect(r.height == 50);
    try std.testing.expect(r.corner_radius == 5);
    try std.testing.expect(r.border_style == .dashed);
}

test "Circle: construction" {
    const c = Circle{ .cx = 50, .cy = 50, .radius = 25 };
    try std.testing.expect(c.cx == 50);
    try std.testing.expect(c.radius == 25);
    try std.testing.expect(c.border_style == .solid);
}

test "Ellipse: construction" {
    const e = Ellipse{ .cx = 100, .cy = 75, .rx = 40, .ry = 20 };
    try std.testing.expect(e.rx == 40);
    try std.testing.expect(e.ry == 20);
}

test "Arc: construction" {
    const a = Arc{ .cx = 0, .cy = 0, .radius = 30, .start_angle = 0, .end_angle = 3.14159 };
    try std.testing.expect(a.radius == 30);
    try std.testing.expect(a.end_angle > 3.14);
}

test "Polygon: construction with points" {
    const pts = [_]Point{
        .{ .x = 0, .y = -20 },
        .{ .x = 20, .y = 0 },
        .{ .x = 0, .y = 20 },
        .{ .x = -20, .y = 0 },
    };
    const poly = Polygon{ .points = &pts };
    try std.testing.expectEqual(@as(usize, 4), poly.points.len);
    try std.testing.expect(poly.points[0].y == -20);
}

test "Line: construction with markers" {
    const l = Line{
        .x1 = 0,
        .y1 = 0,
        .x2 = 100,
        .y2 = 100,
        .style = .dashed,
        .start_marker = .circle,
        .end_marker = .arrow,
    };
    try std.testing.expect(l.style == .dashed);
    try std.testing.expect(l.start_marker == .circle);
    try std.testing.expect(l.end_marker == .arrow);
}

test "Path: construction" {
    const pts = [_]Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 50, .y = 25 },
        .{ .x = 100, .y = 0 },
    };
    const p = Path{
        .points = &pts,
        .is_spline = true,
        .end_marker = .arrow,
    };
    try std.testing.expectEqual(@as(usize, 3), p.points.len);
    try std.testing.expect(p.is_spline);
    try std.testing.expect(p.end_marker == .arrow);
}

test "Text: construction with style" {
    const t = Text{
        .x = 50,
        .y = 25,
        .content = "Hello World",
        .alignment = .left,
        .style = .{ .bold = true, .italic = true },
    };
    try std.testing.expectEqualStrings("Hello World", t.content);
    try std.testing.expect(t.alignment == .left);
    try std.testing.expect(t.style.bold);
    try std.testing.expect(t.style.italic);
    try std.testing.expect(!t.style.dim);
}

test "Group: construction with children" {
    const children = [_]DrawingPrimitive{
        .{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 50 } },
        .{ .text = .{ .x = 50, .y = 25, .content = "Label" } },
    };
    const g = Group{
        .children = &children,
        .label = "Subgraph A",
        .border_style = .solid,
        .x = 0,
        .y = 0,
        .width = 120,
        .height = 70,
    };
    try std.testing.expectEqual(@as(usize, 2), g.children.len);
    try std.testing.expectEqualStrings("Subgraph A", g.label.?);
}

test "DrawingPrimitive: tagged union discrimination" {
    const prim_rect: DrawingPrimitive = .{ .rect = .{ .width = 42 } };
    const prim_circle: DrawingPrimitive = .{ .circle = .{ .radius = 10 } };
    const prim_text: DrawingPrimitive = .{ .text = .{ .content = "hi" } };

    try std.testing.expect(prim_rect == .rect);
    try std.testing.expect(prim_circle == .circle);
    try std.testing.expect(prim_text == .text);
    try std.testing.expect(prim_rect.rect.width == 42);
}

test "Fill: solid color" {
    const fill = Fill{ .solid = .{ .r = 255, .g = 128, .b = 0 } };
    try std.testing.expect(fill == .solid);
    try std.testing.expectEqual(@as(u8, 255), fill.solid.r);
}

test "Fill: gradient" {
    const fill = Fill{ .gradient = .{
        .start_color = .{ .r = 255, .g = 0, .b = 0 },
        .end_color = .{ .r = 0, .g = 0, .b = 255 },
        .direction = .horizontal,
    } };
    try std.testing.expect(fill == .gradient);
    try std.testing.expectEqual(@as(u8, 255), fill.gradient.start_color.r);
    try std.testing.expectEqual(@as(u8, 255), fill.gradient.end_color.b);
}

test "TextStyle: composable flags" {
    const s = TextStyle{ .bold = true, .underline = true };
    try std.testing.expect(s.bold);
    try std.testing.expect(!s.dim);
    try std.testing.expect(!s.italic);
    try std.testing.expect(s.underline);
}

test "MarkerType: all variants exist" {
    const markers = [_]MarkerType{
        .none,           .arrow,          .hollow_arrow,
        .diamond,        .hollow_diamond, .circle,
        .crow_foot_one,  .crow_foot_many, .crow_foot_zero_one,
        .crow_foot_zero_many,
    };
    try std.testing.expectEqual(@as(usize, 10), markers.len);
}

test "Drawing: init and add primitives" {
    const allocator = std.testing.allocator;

    var drawing = Drawing.init(allocator);
    defer drawing.deinit();

    try drawing.addPrimitive(.{ .rect = .{ .x = 0, .y = 0, .width = 100, .height = 50 } });
    try drawing.addPrimitive(.{ .text = .{ .x = 50, .y = 25, .content = "Node A" } });
    try drawing.addPrimitive(.{ .circle = .{ .cx = 200, .cy = 100, .radius = 15 } });

    try std.testing.expectEqual(@as(usize, 3), drawing.primitives.items.len);
    try std.testing.expect(drawing.primitives.items[0] == .rect);
    try std.testing.expect(drawing.primitives.items[1] == .text);
    try std.testing.expect(drawing.primitives.items[2] == .circle);
}

test "Drawing: set dimensions" {
    const allocator = std.testing.allocator;

    var drawing = Drawing.init(allocator);
    defer drawing.deinit();

    drawing.setDimensions(800, 600);
    try std.testing.expect(drawing.width == 800);
    try std.testing.expect(drawing.height == 600);
}
