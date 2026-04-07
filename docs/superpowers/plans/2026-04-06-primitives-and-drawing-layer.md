# Primitives & Drawing Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a DrawingIR layer between layout and rendering, extend the graph engine with node shapes, edge decorators, and card sections — laying the foundation for multi-primitive diagramming (flowcharts, ER diagrams, class diagrams, etc.) while preserving backwards compatibility.

**Architecture:** A new `src/drawing/` module defines renderer-agnostic drawing primitives (Rect, Circle, Polygon, Path, Text, Group, etc.). LayoutIR converts to DrawingIR via `convert.zig`. The existing graph engine gains `NodeShape`, `EdgeDecorator`, and `CardSection` extensions. Existing `terminal.render(layout_ir)` and `svg.render(layout_ir)` keep working unchanged.

**Tech Stack:** Zig 0.14.0, zero external dependencies. Follows existing conventions: `ArrayListUnmanaged` + explicit allocators, `comptime` test discovery, tagged unions for variant types.

**Branch:** `feat/bus-style-edge-routing` (builds on existing work)

---

## File Structure

### New files to create:
| File | Responsibility |
|------|---------------|
| `src/drawing/ir.zig` | DrawingIR types: Point, Rect, Circle, Ellipse, Arc, Polygon, Line, Path, Text, Group, DrawingPrimitive tagged union, style types |
| `src/drawing/convert.zig` | LayoutIR → DrawingIR conversion: nodes→Rect+Text, edges→Path+markers, subgraphs→Group |
| `src/core/shapes.zig` | Shape vertex generation: given NodeShape + center + width + height → polygon vertices or circle/ellipse params |

### Existing files to modify:
| File | Changes |
|------|---------|
| `src/core/graph.zig` | Add `NodeShape` enum, `shape` field to `NodeOptions`/`Node`; add `EdgeDecorator`, `LineStyle`, `MarkerType` to `Edge`; add `CardSection`, `CardField`, `Visibility`, `Constraint`, `sections` field to `NodeOptions`/`Node` |
| `src/core/ir.zig` | Add `shape` to `LayoutNode`; add `line_style`, `start_marker`, `end_marker` to `LayoutEdge`; propagate through `convertCoord` |
| `src/render/terminal/card.zig` | Extend `paintCard` to render multi-section cards with field visibility/type/constraint prefixes |
| `src/render/terminal/card_tests.zig` | Add tests for sectioned card rendering |
| `src/root.zig` | Re-export `drawing`, `shapes`, new graph types |

---

## Task 1: DrawingIR types

Define all drawing primitives in a new `src/drawing/ir.zig` module. This is the shared intermediate representation that all future renderers will consume.

**Files:**
- Create: `src/drawing/ir.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Write failing tests for DrawingIR type construction**

Create `src/drawing/ir.zig` with tests at the bottom but no implementation types yet. Start with the full file — types + tests together (Zig convention: tests live in the same file as the code they test).

Create `src/drawing/ir.zig`:

```zig
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
```

- [ ] **Step 2: Wire up the module for test discovery**

Modify `src/root.zig` — add the drawing module re-export alongside the existing core imports:

Add after the `pub const ir = @import("core/ir.zig");` line:

```zig
/// Drawing IR — renderer-agnostic drawing primitives
pub const drawing = @import("drawing/ir.zig");
pub const DrawingPrimitive = drawing.DrawingPrimitive;
pub const Drawing = drawing.Drawing;
```

Also ensure the drawing directory exists:

```bash
mkdir -p src/drawing
```

- [ ] **Step 3: Run tests — expect them to pass**

```bash
zig build test 2>&1 | head -50
```

Expected: All DrawingIR tests pass. The types are self-contained with no dependencies on other modules.

- [ ] **Step 4: Commit**

```
feat: add DrawingIR types with all drawing primitives

Introduces src/drawing/ir.zig with Point, Rect, Circle, Ellipse, Arc,
Polygon, Line, Path, Text, Group primitives, DrawingPrimitive tagged
union, Drawing container, and style types (BorderStyle, Fill, TextStyle,
MarkerType). All types use f64 coordinates for rendering precision.
```

---

## Task 2: LayoutIR to DrawingIR conversion

Create the bridge that converts existing graph layout output (LayoutIR) into the new DrawingIR. This is the key backwards-compatibility layer — existing renderers can eventually call `toDrawing()` internally.

**Files:**
- Create: `src/drawing/convert.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Write failing tests for LayoutIR → DrawingIR conversion**

Create `src/drawing/convert.zig` with tests that construct LayoutIR manually and verify the DrawingIR output:

```zig
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
                .x = @floatFromInt(sg.x) + 4,
                .y = @floatFromInt(sg.y) + 1,
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
```

- [ ] **Step 2: Wire up the module for test discovery**

Add to `src/root.zig` after the `drawing` import:

```zig
/// Drawing IR conversion (LayoutIR → DrawingIR)
pub const drawing_convert = @import("drawing/convert.zig");
pub const convertLayoutIR = drawing_convert.convertLayoutIR;
```

- [ ] **Step 3: Run tests — expect them to pass**

```bash
zig build test 2>&1 | head -50
```

Expected: All conversion tests pass. The `corner` edge test verifies the 4-point L-shaped path. The subgraph test verifies Group creation.

- [ ] **Step 4: Commit**

```
feat: add LayoutIR to DrawingIR conversion

Introduces src/drawing/convert.zig with convertLayoutIR() that maps
LayoutNodes to Rect+Text, LayoutEdges to Line/Path with markers,
and SubgraphInfo to Group primitives. Handles all EdgePath variants
(direct, corner, multi_segment, spline, side_channel, bus).
```

---

## Task 3: Node shapes and polygon vertex generation

Add a `NodeShape` enum to the graph model and create `src/core/shapes.zig` with vertex generation functions. Given a shape, center point, width, and height, it returns the polygon vertices (or circle/ellipse parameters).

**Files:**
- Create: `src/core/shapes.zig`
- Modify: `src/core/graph.zig` (add `NodeShape` enum and `shape` field)
- Modify: `src/core/ir.zig` (add `shape` field to `LayoutNode`, propagate in `convertCoord`)
- Modify: `src/root.zig` (re-export new types)

- [ ] **Step 1: Add NodeShape to graph.zig**

In `src/core/graph.zig`, add the `NodeShape` enum before `NodeOptions`:

```zig
/// Shape of a node when rendered.
/// Terminal renderer approximates these with box-drawing/ASCII art.
/// SVG renderer emits actual geometric shapes.
pub const NodeShape = enum {
    rect,
    rounded_rect,
    diamond,
    parallelogram,
    cylinder,
    stadium,
    circle,
    hexagon,
    trapezoid,
    double_circle,
    subroutine,
    asymmetric,
};
```

Add `shape` field to `NodeOptions`:

```zig
pub const NodeOptions = struct {
    label: []const u8 = "",
    width: usize = 0,
    height: usize = 1,
    pin: ?Pin = null,
    lines: []const []const u8 = &.{},
    /// Node shape (default: rect)
    shape: NodeShape = .rect,
};
```

Add `shape` field to `Node`:

```zig
pub const Node = struct {
    id: usize,
    label: []const u8,
    width: usize,
    height: usize = 1,
    owned_label: bool = false,
    kind: NodeKind = .explicit,
    pin: ?Pin = null,
    lines: []const []const u8 = &.{},
    /// Node shape for rendering
    shape: NodeShape = .rect,
    // ... rest unchanged
};
```

Update `Node.initFromOptions` to propagate the shape:

```zig
pub fn initFromOptions(id: usize, opts: NodeOptions) Node {
    // ... existing width/height logic ...
    return .{
        .id = id,
        .label = opts.label,
        .width = effective_width,
        .height = effective_height,
        .pin = opts.pin,
        .lines = opts.lines,
        .shape = opts.shape,
    };
}
```

- [ ] **Step 2: Add shape to LayoutNode in ir.zig**

In `src/core/ir.zig`, add to the `LayoutNode` struct:

```zig
/// Node shape for rendering (from graph model)
shape: graph_mod.NodeShape = .rect,
```

In `convertCoord`, propagate the shape in the node conversion:

```zig
try result.addNode(.{
    .id = node.id,
    .label = node.label,
    .lines = node.lines,
    .x = coordCast(Target, Coord, node.x),
    .y = coordCast(Target, Coord, node.y),
    .width = coordCast(Target, Coord, node.width),
    .height = coordCast(Target, Coord, node.height),
    .center_x = coordCast(Target, Coord, node.center_x),
    .center_y = coordCast(Target, Coord, node.center_y),
    .level = node.level,
    .level_position = node.level_position,
    .kind = node.kind,
    .edge_index = node.edge_index,
    .shape = node.shape,
});
```

- [ ] **Step 3: Create shapes.zig with vertex generation**

Create `src/core/shapes.zig`:

```zig
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
            vertex_buf[0] = .{ .x = cx - hw + skew, .y = cy - hh }; // top-left
            vertex_buf[1] = .{ .x = cx + hw + skew, .y = cy - hh }; // top-right
            vertex_buf[2] = .{ .x = cx + hw - skew, .y = cy + hh }; // bottom-right
            vertex_buf[3] = .{ .x = cx - hw - skew, .y = cy + hh }; // bottom-left (intentional: different skew direction)
            // Correct: parallelogram skews consistently
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
```

- [ ] **Step 4: Wire up re-exports in root.zig**

Add to `src/root.zig`:

```zig
/// Node shape definitions
pub const shapes = @import("core/shapes.zig");
pub const NodeShape = graph.NodeShape;
```

- [ ] **Step 5: Run tests — expect them to pass**

```bash
zig build test 2>&1 | head -50
```

Expected: All shape tests pass. Vertex positions match expected coordinates.

- [ ] **Step 6: Commit**

```
feat: add NodeShape enum and polygon vertex generation

Adds NodeShape enum (rect, diamond, hexagon, etc.) to NodeOptions and
Node in graph.zig, propagates shape through LayoutNode in ir.zig, and
creates src/core/shapes.zig with generateShape() for computing polygon
vertices given shape, center, width, height.
```

---

## Task 4: Edge decorators

Add `EdgeDecorator` with `LineStyle` and `MarkerType` to the graph model edge options, and propagate decorator info through LayoutEdge so renderers can style edges with dashed lines, crow's foot endings, etc.

**Files:**
- Modify: `src/core/graph.zig` (add `LineStyle`, `MarkerType`, `EdgeDecorator`, `EdgeOptions`, update `Edge`)
- Modify: `src/core/ir.zig` (add decorator fields to `LayoutEdge`, propagate in `convertCoord`)
- Modify: `src/root.zig` (re-export new types)

- [ ] **Step 1: Add edge decorator types to graph.zig**

In `src/core/graph.zig`, add before the `Edge` struct:

```zig
/// Line rendering style for edges.
pub const LineStyle = enum {
    solid,
    dashed,
    dotted,
    bold,
};

/// Marker types for edge endpoints.
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

/// Edge styling: line style + endpoint markers.
pub const EdgeDecorator = struct {
    line_style: LineStyle = .solid,
    start_marker: MarkerType = .none,
    end_marker: MarkerType = .arrow,
};
```

Add `decorator` field to `Edge`:

```zig
pub const Edge = struct {
    from: usize,
    to: usize,
    directed: bool = true,
    label: ?[]const u8 = null,
    /// Edge styling (line style + markers)
    decorator: EdgeDecorator = .{},
};
```

- [ ] **Step 2: Add decorator fields to LayoutEdge in ir.zig**

In `src/core/ir.zig`, add to the `LayoutEdge` struct fields:

```zig
/// Edge line style from graph model
line_style: graph_mod.LineStyle = .solid,
/// Start marker from graph model
start_marker: graph_mod.MarkerType = .none,
/// End marker from graph model
end_marker: graph_mod.MarkerType = .arrow,
```

In `convertCoord`, propagate the new fields in the edge conversion:

```zig
result.edges.append(target_allocator, .{
    .from_id = edge.from_id,
    .to_id = edge.to_id,
    .from_x = coordCast(Target, Coord, edge.from_x),
    .from_y = coordCast(Target, Coord, edge.from_y),
    .to_x = coordCast(Target, Coord, edge.to_x),
    .to_y = coordCast(Target, Coord, edge.to_y),
    .path = converted_path,
    .edge_index = edge.edge_index,
    .directed = edge.directed,
    .reversed = edge.reversed,
    .label = edge.label,
    .label_x = coordCast(Target, Coord, edge.label_x),
    .label_y = coordCast(Target, Coord, edge.label_y),
    .line_style = edge.line_style,
    .start_marker = edge.start_marker,
    .end_marker = edge.end_marker,
}) catch |err| {
    var p = converted_path;
    p.deinit();
    return err;
};
```

- [ ] **Step 3: Write tests**

Add tests at the bottom of `src/core/graph.zig` (after existing tests, if any) or add a new test block:

```zig
test "EdgeDecorator: default values" {
    const dec = EdgeDecorator{};
    try std.testing.expect(dec.line_style == .solid);
    try std.testing.expect(dec.start_marker == .none);
    try std.testing.expect(dec.end_marker == .arrow);
}

test "EdgeDecorator: ER diagram style" {
    const dec = EdgeDecorator{
        .line_style = .solid,
        .start_marker = .crow_foot_many,
        .end_marker = .crow_foot_one,
    };
    try std.testing.expect(dec.start_marker == .crow_foot_many);
    try std.testing.expect(dec.end_marker == .crow_foot_one);
}

test "Edge: carries decorator" {
    const edge = Edge{
        .from = 1,
        .to = 2,
        .decorator = .{
            .line_style = .dashed,
            .end_marker = .hollow_arrow,
        },
    };
    try std.testing.expect(edge.decorator.line_style == .dashed);
    try std.testing.expect(edge.decorator.end_marker == .hollow_arrow);
}
```

Add test at the bottom of `src/core/ir.zig`:

```zig
test "LayoutEdge: decorator fields propagate through convertCoord" {
    const allocator = std.testing.allocator;

    var source = TestLayoutIR.init(allocator);
    defer source.deinit();

    try source.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 10,
        .from_y = 5,
        .to_x = 10,
        .to_y = 15,
        .path = .{ .direct = {} },
        .edge_index = 0,
        .line_style = .dashed,
        .start_marker = .circle,
        .end_marker = .crow_foot_many,
    });
    source.setDimensions(40, 20);

    var converted = try source.convertCoord(f32, allocator);
    defer converted.deinit();

    const edge = converted.edges.items[0];
    try std.testing.expect(edge.line_style == .dashed);
    try std.testing.expect(edge.start_marker == .circle);
    try std.testing.expect(edge.end_marker == .crow_foot_many);
}
```

- [ ] **Step 4: Re-export in root.zig**

Add to `src/root.zig`:

```zig
pub const LineStyle = graph.LineStyle;
pub const MarkerType = graph.MarkerType;
pub const EdgeDecorator = graph.EdgeDecorator;
```

- [ ] **Step 5: Run tests — expect them to pass**

```bash
zig build test 2>&1 | head -50
```

Expected: All tests pass, including the convertCoord propagation test.

- [ ] **Step 6: Commit**

```
feat: add EdgeDecorator with LineStyle and MarkerType

Adds LineStyle (solid/dashed/dotted/bold), MarkerType (arrow, crow's
foot variants, diamond, circle, etc.), and EdgeDecorator struct to
graph.zig Edge. Propagates line_style, start_marker, end_marker
through LayoutEdge in ir.zig including convertCoord.
```

---

## Task 5: Card node extensions with sections

Extend card nodes to support multiple sections with typed fields, visibility markers, and constraints — enabling ER diagrams and class diagrams.

**Files:**
- Modify: `src/core/graph.zig` (add `CardSection`, `CardField`, `Visibility`, `Constraint`, `sections` field to `NodeOptions`/`Node`)
- Modify: `src/core/ir.zig` (add `sections` field to `LayoutNode`, propagate in `convertCoord`)
- Modify: `src/render/terminal/card.zig` (extend `paintCard` for sectioned rendering)
- Modify: `src/render/terminal/card_tests.zig` (add section tests)
- Modify: `src/root.zig` (re-export new types)

- [ ] **Step 1: Add card section types to graph.zig**

In `src/core/graph.zig`, add before `NodeOptions`:

```zig
/// Visibility modifier for class diagram fields/methods.
pub const Visibility = enum {
    none,
    public,    // +
    private,   // -
    protected, // #
};

/// Constraint on a database field.
pub const Constraint = enum {
    pk,
    fk,
    not_null,
    unique,
    auto_increment,
};

/// A field within a card section.
pub const CardField = struct {
    name: []const u8,
    type_name: ?[]const u8 = null,
    visibility: Visibility = .none,
    constraints: []const Constraint = &.{},
};

/// A named section within a card node (e.g., "Fields", "Methods").
pub const CardSection = struct {
    title: ?[]const u8 = null,
    fields: []const CardField = &.{},
};
```

Add `sections` to `NodeOptions`:

```zig
pub const NodeOptions = struct {
    label: []const u8 = "",
    width: usize = 0,
    height: usize = 1,
    pin: ?Pin = null,
    lines: []const []const u8 = &.{},
    shape: NodeShape = .rect,
    /// Multi-section card content (for ER/class diagrams).
    /// When set, overrides `lines` for rendering.
    sections: []const CardSection = &.{},
};
```

Add `sections` to `Node`:

```zig
pub const Node = struct {
    // ... existing fields ...
    /// Multi-section card content (empty = use lines or simple label)
    sections: []const CardSection = &.{},
    // ...
};
```

Update `Node.initFromOptions` to handle sections:

```zig
pub fn initFromOptions(id: usize, opts: NodeOptions) Node {
    var effective_width = if (opts.width > 0) opts.width else opts.label.len + 2;
    var effective_height = opts.height;

    if (opts.sections.len > 0) {
        // Sectioned card: compute dimensions from sections
        // Width = max(label, all field display strings) + 2 (borders)
        for (opts.sections) |section| {
            if (section.title) |title| {
                if (title.len + 2 > effective_width) {
                    effective_width = title.len + 2;
                }
            }
            for (section.fields) |field| {
                // Display: "X name: type CCC" where X=visibility, CCC=constraints
                var field_len: usize = field.name.len;
                if (field.visibility != .none) field_len += 2; // "+ " prefix
                if (field.type_name) |tn| field_len += tn.len + 2; // ": type"
                if (field.constraints.len > 0) field_len += field.constraints.len * 3; // " PK" etc
                if (field_len + 2 > effective_width) {
                    effective_width = field_len + 2;
                }
            }
        }
        // Height = top(1) + header(1) + per section: sep(1) + field_count + bottom(1)
        if (opts.height == 1) {
            var h: usize = 3; // top + header + bottom
            for (opts.sections) |section| {
                h += 1; // separator line
                h += section.fields.len;
            }
            effective_height = h;
        }
    } else if (opts.lines.len > 0) {
        for (opts.lines) |line| {
            if (line.len + 2 > effective_width) {
                effective_width = line.len + 2;
            }
        }
        if (opts.height == 1) {
            effective_height = opts.lines.len + 4;
        }
    }

    return .{
        .id = id,
        .label = opts.label,
        .width = effective_width,
        .height = effective_height,
        .pin = opts.pin,
        .lines = opts.lines,
        .shape = opts.shape,
        .sections = opts.sections,
    };
}
```

- [ ] **Step 2: Add sections to LayoutNode in ir.zig**

Add to the `LayoutNode` struct:

```zig
/// Multi-section card content (empty = use lines or simple label).
/// Borrowed from the Graph node — valid as long as the Graph is alive.
sections: []const graph_mod.CardSection = &.{},
```

In `convertCoord`, propagate sections in node conversion:

```zig
try result.addNode(.{
    .id = node.id,
    .label = node.label,
    .lines = node.lines,
    .sections = node.sections,
    .x = coordCast(Target, Coord, node.x),
    // ... rest unchanged
});
```

- [ ] **Step 3: Add helper functions to card.zig for sectioned rendering**

In `src/render/terminal/card.zig`, add a helper to format a field as a display string and a function to compute sectioned card dimensions:

```zig
/// Format a visibility marker as a single character.
pub fn visibilityChar(vis: graph_mod.Visibility) u8 {
    return switch (vis) {
        .none => ' ',
        .public => '+',
        .private => '-',
        .protected => '#',
    };
}

/// Format a constraint as a short string.
pub fn constraintStr(c: graph_mod.Constraint) []const u8 {
    return switch (c) {
        .pk => "PK",
        .fk => "FK",
        .not_null => "NN",
        .unique => "UQ",
        .auto_increment => "AI",
    };
}

/// Compute width for a sectioned card.
pub fn sectionedCardWidth(header: []const u8, sections: []const graph_mod.CardSection) usize {
    var max_len = header.len;
    for (sections) |section| {
        if (section.title) |title| {
            if (title.len > max_len) max_len = title.len;
        }
        for (section.fields) |field| {
            var field_len: usize = field.name.len;
            if (field.visibility != .none) field_len += 2;
            if (field.type_name) |tn| field_len += tn.len + 2;
            for (field.constraints) |_| field_len += 3;
            if (field_len > max_len) max_len = field_len;
        }
    }
    return max_len + 2; // borders
}

/// Compute height for a sectioned card.
pub fn sectionedCardHeight(sections: []const graph_mod.CardSection) usize {
    var h: usize = 3; // top + header + bottom
    for (sections) |section| {
        h += 1; // separator
        h += section.fields.len;
    }
    return h;
}

/// Paint a sectioned card on the buffer.
pub fn paintSectionedCard(
    buffer: *Buffer2D,
    x: usize,
    y: usize,
    width: usize,
    header: []const u8,
    sections: []const graph_mod.CardSection,
    style: CardStyle,
) void {
    if (width < 2) return;
    const inner_w = width - 2;
    const bc = boxCharsFor(style.border);
    const border_cc = resolveColorAt(style.border_color, 0.0);
    const header_cc = resolveColorAt(style.header_color, 0.0);
    const content_cc = resolveColorAt(style.content_color, 0.0);

    // Top border
    buffer.setWithColor(x, y, bc.tl, border_cc);
    for (1..width - 1) |col| {
        buffer.setWithColor(x + col, y, bc.h, border_cc);
    }
    buffer.setWithColor(x + width - 1, y, bc.tr, border_cc);

    // Header row
    buffer.setWithColor(x, y + 1, bc.v, border_cc);
    const pad = if (inner_w > header.len) (inner_w - header.len) / 2 else 0;
    for (0..inner_w) |col| {
        const idx = if (col >= pad and col < pad + header.len) col - pad else inner_w;
        if (idx < header.len) {
            buffer.setWithColor(x + 1 + col, y + 1, header[idx], header_cc);
            if (@as(u8, @bitCast(style.header_attrs)) != 0) {
                buffer.setAttrs(x + 1 + col, y + 1, style.header_attrs);
            }
        } else {
            buffer.set(x + 1 + col, y + 1, ' ');
        }
    }
    buffer.setWithColor(x + width - 1, y + 1, bc.v, border_cc);

    // Sections
    var row = y + 2;
    for (sections) |section| {
        // Separator line
        buffer.setWithColor(x, row, 0x251C, border_cc);
        for (1..width - 1) |col| {
            buffer.setWithColor(x + col, row, bc.h, border_cc);
        }
        buffer.setWithColor(x + width - 1, row, 0x2524, border_cc);
        row += 1;

        // Fields
        for (section.fields) |field| {
            buffer.setWithColor(x, row, bc.v, border_cc);
            var col: usize = 0;

            // Visibility prefix
            if (field.visibility != .none) {
                if (col < inner_w) {
                    buffer.setWithColor(x + 1 + col, row, visibilityChar(field.visibility), content_cc);
                    col += 1;
                }
                if (col < inner_w) {
                    buffer.set(x + 1 + col, row, ' ');
                    col += 1;
                }
            }

            // Field name
            for (field.name) |ch| {
                if (col < inner_w) {
                    buffer.setWithColor(x + 1 + col, row, ch, content_cc);
                    col += 1;
                }
            }

            // Type name
            if (field.type_name) |tn| {
                if (col + 2 <= inner_w) {
                    buffer.set(x + 1 + col, row, ':');
                    col += 1;
                    buffer.set(x + 1 + col, row, ' ');
                    col += 1;
                }
                for (tn) |ch| {
                    if (col < inner_w) {
                        buffer.setWithColor(x + 1 + col, row, ch, content_cc);
                        col += 1;
                    }
                }
            }

            // Constraints
            for (field.constraints) |constraint| {
                if (col < inner_w) {
                    buffer.set(x + 1 + col, row, ' ');
                    col += 1;
                }
                for (constraintStr(constraint)) |ch| {
                    if (col < inner_w) {
                        buffer.setWithColor(x + 1 + col, row, ch, content_cc);
                        col += 1;
                    }
                }
            }

            // Pad remaining
            while (col < inner_w) : (col += 1) {
                buffer.set(x + 1 + col, row, ' ');
            }
            buffer.setWithColor(x + width - 1, row, bc.v, border_cc);
            row += 1;
        }
    }

    // Bottom border
    buffer.setWithColor(x, row, bc.bl, border_cc);
    for (1..width - 1) |col| {
        buffer.setWithColor(x + col, row, bc.h, border_cc);
    }
    buffer.setWithColor(x + width - 1, row, bc.br, border_cc);
}
```

Also add at the top of `card.zig`, alongside existing imports:

```zig
const graph_mod = @import("../../core/graph.zig");
```

- [ ] **Step 4: Write tests in card_tests.zig**

Append to `src/render/terminal/card_tests.zig`:

```zig
test "card: sectioned card width calculation" {
    const sections = [_]graph_mod.CardSection{
        .{
            .title = "Fields",
            .fields = &.{
                .{ .name = "id", .type_name = "INT", .constraints = &.{.pk} },
                .{ .name = "name", .type_name = "TEXT" },
            },
        },
    };
    const width = card.sectionedCardWidth("users", &sections);
    // "id: INT PK" = 10 chars, "name: TEXT" = 10 chars, "users" = 5 chars
    // max is 10 + borders = 12
    try std.testing.expect(width >= 12);
}

test "card: sectioned card height calculation" {
    const sections = [_]graph_mod.CardSection{
        .{
            .fields = &.{
                .{ .name = "id" },
                .{ .name = "name" },
            },
        },
        .{
            .fields = &.{
                .{ .name = "validate()" },
            },
        },
    };
    // top(1) + header(1) + sep(1) + 2 fields + sep(1) + 1 field + bottom(1) = 8
    try std.testing.expectEqual(@as(usize, 8), card.sectionedCardHeight(&sections));
}

test "card: paint sectioned card renders header and fields" {
    const allocator = std.testing.allocator;
    var buf = try Buffer2D.init(allocator, 25, 10);
    defer buf.deinit(allocator);

    const sections = [_]graph_mod.CardSection{
        .{
            .fields = &.{
                .{ .name = "id", .type_name = "INT", .visibility = .public, .constraints = &.{.pk} },
                .{ .name = "email", .type_name = "TEXT", .visibility = .private },
            },
        },
    };
    card.paintSectionedCard(&buf, 0, 0, 20, "users", &sections, .{});

    // Top-left corner
    try std.testing.expectEqual(@as(u21, 0x250C), buf.get(0, 0));
    // Bottom-left corner at row = 2 + 1(sep) + 2(fields) + 1(bottom) - 1 = 5
    // Actually: top(0) + header(1) + sep(2) + 2 fields(3,4) + bottom(5)
    try std.testing.expectEqual(@as(u21, 0x2514), buf.get(0, 5));
    // Separator at row 2
    try std.testing.expectEqual(@as(u21, 0x251C), buf.get(0, 2));
    // First field row 3: visibility '+' at col 1
    try std.testing.expectEqual(@as(u21, '+'), buf.get(1, 3));
    // Second field row 4: visibility '-' at col 1
    try std.testing.expectEqual(@as(u21, '-'), buf.get(1, 4));
}

test "card: visibility char mapping" {
    try std.testing.expectEqual(@as(u8, '+'), card.visibilityChar(.public));
    try std.testing.expectEqual(@as(u8, '-'), card.visibilityChar(.private));
    try std.testing.expectEqual(@as(u8, '#'), card.visibilityChar(.protected));
    try std.testing.expectEqual(@as(u8, ' '), card.visibilityChar(.none));
}

test "card: constraint string mapping" {
    try std.testing.expectEqualStrings("PK", card.constraintStr(.pk));
    try std.testing.expectEqualStrings("FK", card.constraintStr(.fk));
    try std.testing.expectEqualStrings("NN", card.constraintStr(.not_null));
    try std.testing.expectEqualStrings("UQ", card.constraintStr(.unique));
    try std.testing.expectEqualStrings("AI", card.constraintStr(.auto_increment));
}
```

Also add the graph_mod import at the top of `card_tests.zig`:

```zig
const graph_mod = @import("../../core/graph.zig");
```

- [ ] **Step 5: Add graph.zig tests for sections**

Add at the bottom of the test section in `src/core/graph.zig`:

```zig
test "CardSection: field with visibility and constraints" {
    const field = CardField{
        .name = "id",
        .type_name = "INT",
        .visibility = .public,
        .constraints = &.{ .pk, .auto_increment },
    };
    try std.testing.expectEqualStrings("id", field.name);
    try std.testing.expectEqualStrings("INT", field.type_name.?);
    try std.testing.expect(field.visibility == .public);
    try std.testing.expectEqual(@as(usize, 2), field.constraints.len);
}

test "Node.initFromOptions: sections compute height" {
    const sections = [_]CardSection{
        .{
            .fields = &.{
                .{ .name = "id" },
                .{ .name = "name" },
            },
        },
    };
    const node = Node.initFromOptions(1, .{
        .label = "users",
        .sections = &sections,
    });
    // top(1) + header(1) + sep(1) + 2 fields + bottom(1) = 6
    try std.testing.expectEqual(@as(usize, 6), node.height);
    try std.testing.expectEqual(@as(usize, 1), node.sections.len);
}
```

- [ ] **Step 6: Re-export in root.zig**

Add to `src/root.zig`:

```zig
pub const Visibility = graph.Visibility;
pub const Constraint = graph.Constraint;
pub const CardField = graph.CardField;
pub const CardSection = graph.CardSection;
```

- [ ] **Step 7: Run tests — expect them to pass**

```bash
zig build test 2>&1 | head -50
```

Expected: All tests pass, including sectioned card rendering with correct visibility markers and field positions.

- [ ] **Step 8: Commit**

```
feat: add card node sections with fields, visibility, and constraints

Extends card nodes with CardSection, CardField, Visibility, and
Constraint types for ER/class diagram support. NodeOptions gains
sections field. Terminal card renderer paints multi-section boxes
with visibility markers (+/-/#) and constraint labels (PK/FK/NN).
```

---

## Task 6: Subgraph styling

Add style variants to subgraphs for C4 and network topology diagrams.

**Files:**
- Modify: `src/core/graph.zig` (add `SubgraphStyleKind` enum and `style` field to `Subgraph`)
- Modify: `src/core/ir.zig` (add `style` field to `SubgraphInfo`)

- [ ] **Step 1: Write failing test for SubgraphStyleKind**

Add to the bottom of `src/core/graph.zig`:

```zig
test "subgraph: style field defaults to .default" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addSubgraph(0, "Backend", null);
    const sg = g.subgraphs.items[0];
    try std.testing.expectEqual(SubgraphStyleKind.default, sg.style);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `SubgraphStyleKind` not defined

- [ ] **Step 3: Implement SubgraphStyleKind and add to Subgraph**

Add above `Subgraph` in `src/core/graph.zig`:

```zig
/// Visual style for subgraph boundaries.
pub const SubgraphStyleKind = enum {
    default,    // solid border
    dashed,     // dashed border
    cloud,      // cloud shape (SVG) / dashed rounded (terminal)
    zone,       // shaded background region
    system,     // C4 system boundary — bold border
    container,  // C4 container boundary — dashed border
    component,  // C4 component boundary — dotted border
};
```

Add `style: SubgraphStyleKind = .default,` to the `Subgraph` struct.

Add `style` field to `SubgraphInfo` in `src/core/ir.zig`:

```zig
style: @import("graph.zig").SubgraphStyleKind = .default,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 5: Commit**

```
feat: add SubgraphStyleKind for C4/network topology subgraph styles

Adds default, dashed, cloud, zone, system, container, component
variants. Propagated through Subgraph → SubgraphInfo → renderers.
```

---

## Task 7: Terminal DrawingIR renderer

Add `renderDrawing` function to the terminal renderer that takes a `Drawing` and produces text output.

**Files:**
- Create: `src/render/terminal/drawing_renderer.zig`
- Modify: `src/render/terminal/mod.zig` (add import + re-export)

- [ ] **Step 1: Write failing test for terminal DrawingIR rendering**

Create `src/render/terminal/drawing_renderer.zig`:

```zig
//! Terminal renderer for DrawingIR primitives.
//!
//! Maps drawing primitives to Unicode box-drawing characters.

const std = @import("std");
const Allocator = std.mem.Allocator;
const buffer_mod = @import("buffer.zig");
const Buffer2D = buffer_mod.Buffer2D;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;
const DrawingPrimitive = drawing.DrawingPrimitive;

/// Render a Drawing to a text string using Unicode box-drawing characters.
/// Caller owns the returned memory.
pub fn renderDrawing(d: *const Drawing, allocator: Allocator) ![]u8 {
    _ = d;
    _ = allocator;
    return error.NotImplemented;
}

// ============================================================================
// Tests
// ============================================================================

test "drawing terminal: render empty drawing" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(10, 5);

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    // Empty drawing should produce a string of spaces/newlines
    try std.testing.expect(result.len > 0);
}

test "drawing terminal: render single rect" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(20, 5);

    try d.addPrimitive(.{ .rect = .{ .x = 0, .y = 0, .width = 8, .height = 3 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    // Should contain box-drawing characters
    try std.testing.expect(std.mem.indexOf(u8, result, "┌") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "┘") != null);
}

test "drawing terminal: render text primitive" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(20, 3);

    try d.addPrimitive(.{ .text = .{ .x = 2, .y = 1, .content = "Hello" } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
}

test "drawing terminal: render line" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(10, 5);

    // Vertical line
    try d.addPrimitive(.{ .line = .{ .x1 = 3, .y1 = 0, .x2 = 3, .y2 = 4 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    // Should contain vertical line chars
    try std.testing.expect(std.mem.indexOf(u8, result, "│") != null);
}

test "drawing terminal: render circle as dot" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(10, 3);

    try d.addPrimitive(.{ .circle = .{ .cx = 3, .cy = 1, .radius = 0.5 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    // Small circle renders as ●
    try std.testing.expect(result.len > 0);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `error.NotImplemented`

- [ ] **Step 3: Add import to mod.zig**

Add to `src/render/terminal/mod.zig` imports section:

```zig
const drawing_renderer = @import("drawing_renderer.zig");
pub const renderDrawing = drawing_renderer.renderDrawing;
```

- [ ] **Step 4: Implement renderDrawing**

Replace the stub in `src/render/terminal/drawing_renderer.zig`:

```zig
pub fn renderDrawing(d: *const Drawing, allocator: Allocator) ![]u8 {
    const w: usize = @intFromFloat(@ceil(d.width));
    const h: usize = @intFromFloat(@ceil(d.height));
    if (w == 0 or h == 0) return try allocator.dupe(u8, "");

    var buf = try Buffer2D.init(allocator, w, h);
    defer buf.deinit(allocator);

    for (d.primitives.items) |prim| {
        paintPrimitive(&buf, prim);
    }

    return buf.render(allocator);
}

fn paintPrimitive(buf: *Buffer2D, prim: DrawingPrimitive) void {
    switch (prim) {
        .rect => |r| paintRect(buf, r),
        .circle => |c| paintCircle(buf, c),
        .ellipse => |e| paintEllipse(buf, e),
        .text => |t| paintText(buf, t),
        .line => |l| paintLine(buf, l),
        .polygon => |p| paintPolygon(buf, p),
        .group => |g| paintGroup(buf, g),
        .path => |pa| paintPath(buf, pa),
        .arc => {},  // Arc approximated as partial circle — deferred to SVG
    }
}

fn paintRect(buf: *Buffer2D, r: drawing.Rect) void {
    const x: usize = @intFromFloat(@max(0, r.x));
    const y: usize = @intFromFloat(@max(0, r.y));
    const w: usize = @intFromFloat(@max(0, r.width));
    const h: usize = @intFromFloat(@max(0, r.height));
    if (w < 2 or h < 2) return;

    const rounded = r.corner_radius > 0;
    const tl: u21 = if (rounded) 0x256D else 0x250C;
    const tr: u21 = if (rounded) 0x256E else 0x2510;
    const bl: u21 = if (rounded) 0x2570 else 0x2514;
    const br: u21 = if (rounded) 0x256F else 0x2518;

    buf.set(x, y, tl);
    buf.set(x + w - 1, y, tr);
    buf.set(x, y + h - 1, bl);
    buf.set(x + w - 1, y + h - 1, br);

    var col: usize = 1;
    while (col < w - 1) : (col += 1) {
        buf.set(x + col, y, 0x2500);          // ─ top
        buf.set(x + col, y + h - 1, 0x2500);  // ─ bottom
    }
    var row: usize = 1;
    while (row < h - 1) : (row += 1) {
        buf.set(x, y + row, 0x2502);          // │ left
        buf.set(x + w - 1, y + row, 0x2502);  // │ right
    }
}

fn paintCircle(buf: *Buffer2D, c: drawing.Circle) void {
    const cx: usize = @intFromFloat(@max(0, c.cx));
    const cy: usize = @intFromFloat(@max(0, c.cy));
    if (c.radius < 1.0) {
        // Small circle → dot
        buf.set(cx, cy, 0x25CF); // ●
    } else {
        // Larger circle → parentheses approximation
        const r: usize = @intFromFloat(c.radius);
        if (cx >= r) buf.set(cx - r, cy, '(');
        buf.set(cx + r, cy, ')');
    }
}

fn paintEllipse(buf: *Buffer2D, e: drawing.Ellipse) void {
    // Same approximation as circle using horizontal radius
    const cx: usize = @intFromFloat(@max(0, e.cx));
    const cy: usize = @intFromFloat(@max(0, e.cy));
    const rx: usize = @intFromFloat(@max(0, e.rx));
    if (cx >= rx) buf.set(cx - rx, cy, '(');
    buf.set(cx + rx, cy, ')');
}

fn paintText(buf: *Buffer2D, t: drawing.Text) void {
    const x: usize = @intFromFloat(@max(0, t.x));
    const y: usize = @intFromFloat(@max(0, t.y));
    for (t.content, 0..) |ch, i| {
        buf.set(x + i, y, ch);
    }
}

fn paintLine(buf: *Buffer2D, l: drawing.Line) void {
    const x1: usize = @intFromFloat(@max(0, l.x1));
    const y1: usize = @intFromFloat(@max(0, l.y1));
    const x2: usize = @intFromFloat(@max(0, l.x2));
    const y2: usize = @intFromFloat(@max(0, l.y2));

    if (x1 == x2) {
        // Vertical line
        const from_y = @min(y1, y2);
        const to_y = @max(y1, y2);
        var y: usize = from_y;
        while (y <= to_y) : (y += 1) {
            const ch: u21 = if (l.style == .dashed) 0x2506 else 0x2502; // ┆ or │
            buf.set(x1, y, ch);
        }
    } else if (y1 == y2) {
        // Horizontal line
        const from_x = @min(x1, x2);
        const to_x = @max(x1, x2);
        var x: usize = from_x;
        while (x <= to_x) : (x += 1) {
            const ch: u21 = if (l.style == .dashed) 0x2504 else 0x2500; // ┄ or ─
            buf.set(x, y1, ch);
        }
    }
    // Diagonal lines are not well-representable in terminal — skip
}

fn paintPolygon(buf: *Buffer2D, p: drawing.Polygon) void {
    // Draw edges of polygon as lines
    if (p.points.len < 2) return;
    for (0..p.points.len) |i| {
        const a = p.points[i];
        const b = p.points[(i + 1) % p.points.len];
        paintLine(buf, .{
            .x1 = a.x,
            .y1 = a.y,
            .x2 = b.x,
            .y2 = b.y,
        });
    }
}

fn paintGroup(buf: *Buffer2D, g: drawing.Group) void {
    // If group has border, draw it
    if (g.border_style != .none and g.width > 0 and g.height > 0) {
        paintRect(buf, .{
            .x = g.x,
            .y = g.y,
            .width = g.width,
            .height = g.height,
            .border_style = g.border_style,
        });
    }
    // Paint children
    for (g.children) |child| {
        paintPrimitive(buf, child);
    }
}

fn paintPath(buf: *Buffer2D, pa: drawing.Path) void {
    if (pa.points.len < 2) return;
    // Draw each segment as a line
    for (0..pa.points.len - 1) |i| {
        const a = pa.points[i];
        const b = pa.points[i + 1];
        paintLine(buf, .{
            .x1 = a.x,
            .y1 = a.y,
            .x2 = b.x,
            .y2 = b.y,
            .style = pa.style,
        });
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 6: Commit**

```
feat: add terminal DrawingIR renderer

Renders Drawing primitives to Unicode text via Buffer2D. Maps
Rect→box-drawing, Circle→● or (), Text→direct placement,
Line→│/─, Path→multi-segment, Group→optional border + children.
```

---

## Task 8: SVG DrawingIR renderer

Add `renderDrawing` function to the SVG renderer with direct primitive-to-SVG mapping.

**Files:**
- Create: `src/render/svg/drawing_renderer.zig`
- Modify: `src/render/svg/mod.zig` (add import + re-export)

- [ ] **Step 1: Write failing test for SVG DrawingIR rendering**

Create `src/render/svg/drawing_renderer.zig`:

```zig
//! SVG renderer for DrawingIR primitives.
//!
//! Direct mapping: Rect→<rect>, Circle→<circle>, Ellipse→<ellipse>,
//! Line→<line>, Path→<path>, Polygon→<polygon>, Text→<text>, Group→<g>.

const std = @import("std");
const Allocator = std.mem.Allocator;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;
const DrawingPrimitive = drawing.DrawingPrimitive;
const helpers = @import("helpers.zig");

/// Render a Drawing to an SVG string.
/// Caller owns the returned memory.
pub fn renderDrawing(d: *const Drawing, allocator: Allocator) ![]u8 {
    _ = d;
    _ = allocator;
    return error.NotImplemented;
}

test "drawing svg: render empty drawing" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 50);

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "</svg>") != null);
}

test "drawing svg: render rect element" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(200, 100);

    try d.addPrimitive(.{ .rect = .{ .x = 10, .y = 20, .width = 80, .height = 40 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<rect") != null);
}

test "drawing svg: render circle element" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 100);

    try d.addPrimitive(.{ .circle = .{ .cx = 50, .cy = 50, .radius = 25 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<circle") != null);
}

test "drawing svg: render text element" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(200, 50);

    try d.addPrimitive(.{ .text = .{ .x = 10, .y = 25, .content = "Hello" } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<text") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
}

test "drawing svg: render line element" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 100);

    try d.addPrimitive(.{ .line = .{ .x1 = 0, .y1 = 0, .x2 = 100, .y2 = 100 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<line") != null);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `error.NotImplemented`

- [ ] **Step 3: Add import to mod.zig**

Add to `src/render/svg/mod.zig`:

```zig
const drawing_renderer = @import("drawing_renderer.zig");
pub const renderDrawing = drawing_renderer.renderDrawing;
```

- [ ] **Step 4: Implement renderDrawing for SVG**

Replace stub in `src/render/svg/drawing_renderer.zig`:

```zig
pub fn renderDrawing(d: *const Drawing, allocator: Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {d} {d}\">\n", .{
        @as(i64, @intFromFloat(d.width)),
        @as(i64, @intFromFloat(d.height)),
    });

    for (d.primitives.items) |prim| {
        try writePrimitive(w, prim);
    }

    try w.writeAll("</svg>\n");
    return buf.toOwnedSlice();
}

fn writePrimitive(w: anytype, prim: DrawingPrimitive) !void {
    switch (prim) {
        .rect => |r| {
            try w.print("  <rect x=\"{d}\" y=\"{d}\" width=\"{d}\" height=\"{d}\"", .{
                @as(i64, @intFromFloat(r.x)),
                @as(i64, @intFromFloat(r.y)),
                @as(i64, @intFromFloat(r.width)),
                @as(i64, @intFromFloat(r.height)),
            });
            if (r.corner_radius > 0) {
                try w.print(" rx=\"{d}\"", .{@as(i64, @intFromFloat(r.corner_radius))});
            }
            try writeFillStroke(w, r.fill, r.border_style);
            try w.writeAll(" />\n");
        },
        .circle => |c| {
            try w.print("  <circle cx=\"{d}\" cy=\"{d}\" r=\"{d}\"", .{
                @as(i64, @intFromFloat(c.cx)),
                @as(i64, @intFromFloat(c.cy)),
                @as(i64, @intFromFloat(c.radius)),
            });
            try writeFillStroke(w, c.fill, c.border_style);
            try w.writeAll(" />\n");
        },
        .ellipse => |e| {
            try w.print("  <ellipse cx=\"{d}\" cy=\"{d}\" rx=\"{d}\" ry=\"{d}\"", .{
                @as(i64, @intFromFloat(e.cx)),
                @as(i64, @intFromFloat(e.cy)),
                @as(i64, @intFromFloat(e.rx)),
                @as(i64, @intFromFloat(e.ry)),
            });
            try writeFillStroke(w, e.fill, e.border_style);
            try w.writeAll(" />\n");
        },
        .line => |l| {
            try w.print("  <line x1=\"{d}\" y1=\"{d}\" x2=\"{d}\" y2=\"{d}\"", .{
                @as(i64, @intFromFloat(l.x1)),
                @as(i64, @intFromFloat(l.y1)),
                @as(i64, @intFromFloat(l.x2)),
                @as(i64, @intFromFloat(l.y2)),
            });
            try writeStrokeStyle(w, l.style, l.weight);
            try w.writeAll(" />\n");
        },
        .text => |t| {
            try w.print("  <text x=\"{d}\" y=\"{d}\"", .{
                @as(i64, @intFromFloat(t.x)),
                @as(i64, @intFromFloat(t.y)),
            });
            if (t.alignment == .center) try w.writeAll(" text-anchor=\"middle\"");
            if (t.alignment == .right) try w.writeAll(" text-anchor=\"end\"");
            if (t.style.bold) try w.writeAll(" font-weight=\"bold\"");
            if (t.style.italic) try w.writeAll(" font-style=\"italic\"");
            try w.print(" font-size=\"{d}\">", .{@as(i64, @intFromFloat(t.font_size))});
            try helpers.writeXmlEscaped(w, t.content);
            try w.writeAll("</text>\n");
        },
        .polygon => |p| {
            try w.writeAll("  <polygon points=\"");
            for (p.points, 0..) |pt, i| {
                if (i > 0) try w.writeByte(' ');
                try w.print("{d},{d}", .{
                    @as(i64, @intFromFloat(pt.x)),
                    @as(i64, @intFromFloat(pt.y)),
                });
            }
            try w.writeByte('"');
            try writeFillStroke(w, p.fill, p.border_style);
            try w.writeAll(" />\n");
        },
        .path => |pa| {
            if (pa.points.len < 2) return;
            try w.writeAll("  <path d=\"");
            for (pa.points, 0..) |pt, i| {
                const cmd: u8 = if (i == 0) 'M' else 'L';
                try w.print("{c}{d} {d}", .{
                    cmd,
                    @as(i64, @intFromFloat(pt.x)),
                    @as(i64, @intFromFloat(pt.y)),
                });
            }
            try w.writeByte('"');
            try writeStrokeStyle(w, pa.style, pa.weight);
            try w.writeAll(" fill=\"none\" />\n");
        },
        .group => |g| {
            try w.writeAll("  <g>\n");
            for (g.children) |child| {
                try writePrimitive(w, child);
            }
            try w.writeAll("  </g>\n");
        },
        .arc => |a| {
            // SVG arc via path
            const r = a.radius;
            const sx = a.cx + r * @cos(a.start_angle);
            const sy = a.cy + r * @sin(a.start_angle);
            const ex = a.cx + r * @cos(a.end_angle);
            const ey = a.cy + r * @sin(a.end_angle);
            try w.print("  <path d=\"M{d} {d} A{d} {d} 0 0 1 {d} {d}\" fill=\"none\" stroke=\"black\" />\n", .{
                @as(i64, @intFromFloat(sx)),
                @as(i64, @intFromFloat(sy)),
                @as(i64, @intFromFloat(r)),
                @as(i64, @intFromFloat(r)),
                @as(i64, @intFromFloat(ex)),
                @as(i64, @intFromFloat(ey)),
            });
        },
    }
}

fn writeFillStroke(w: anytype, fill: drawing.Fill, border: drawing.BorderStyle) !void {
    switch (fill) {
        .none => try w.writeAll(" fill=\"none\""),
        .solid => |c| try w.print(" fill=\"rgb({d},{d},{d})\"", .{ c.r, c.g, c.b }),
        .gradient => try w.writeAll(" fill=\"none\""),
    }
    if (border == .none) {
        try w.writeAll(" stroke=\"none\"");
    } else {
        try w.writeAll(" stroke=\"black\"");
        if (border == .dashed) try w.writeAll(" stroke-dasharray=\"5,5\"");
        if (border == .dotted) try w.writeAll(" stroke-dasharray=\"2,2\"");
    }
}

fn writeStrokeStyle(w: anytype, style: drawing.BorderStyle, weight: f64) !void {
    try w.writeAll(" stroke=\"black\"");
    if (weight != 1) try w.print(" stroke-width=\"{d}\"", .{@as(i64, @intFromFloat(weight))});
    if (style == .dashed) try w.writeAll(" stroke-dasharray=\"5,5\"");
    if (style == .dotted) try w.writeAll(" stroke-dasharray=\"2,2\"");
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 6: Commit**

```
feat: add SVG DrawingIR renderer

Direct mapping of DrawingIR to SVG elements: Rect→<rect>,
Circle→<circle>, Ellipse→<ellipse>, Line→<line>, Path→<path>,
Polygon→<polygon>, Text→<text>, Group→<g>, Arc→<path>.
```

---

## Task 9: JSON DrawingIR serializer

Add DrawingIR serialization as schema v2.0 alongside existing v1.2.

**Files:**
- Create: `src/render/drawing_json.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Write failing test**

Create `src/render/drawing_json.zig`:

```zig
//! JSON serializer for DrawingIR (schema v2.0).
//!
//! Serializes Drawing primitives to JSON for external tool consumption.

const std = @import("std");
const Allocator = std.mem.Allocator;
const drawing = @import("../drawing/ir.zig");
const Drawing = drawing.Drawing;
const DrawingPrimitive = drawing.DrawingPrimitive;

pub const VERSION = "2.0";

/// Serialize a Drawing as a JSON string.
/// Caller owns the returned memory.
pub fn serialize(d: *const Drawing, allocator: Allocator) ![]u8 {
    _ = d;
    _ = allocator;
    return error.NotImplemented;
}

test "drawing json: serialize empty drawing" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 50);

    const result = try serialize(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"version\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\"primitives\":[]") != null);
}

test "drawing json: serialize rect" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 50);

    try d.addPrimitive(.{ .rect = .{ .x = 10, .y = 20, .width = 50, .height = 30 } });

    const result = try serialize(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"type\":\"rect\"") != null);
}

test "drawing json: serialize text" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(100, 50);

    try d.addPrimitive(.{ .text = .{ .x = 5, .y = 10, .content = "Hello" } });

    const result = try serialize(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "\"type\":\"text\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `error.NotImplemented`

- [ ] **Step 3: Implement serialize**

Replace stub:

```zig
pub fn serialize(d: *const Drawing, allocator: Allocator) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    const w = buf.writer();

    try w.writeAll("{");
    try w.print("\"version\":\"{s}\",", .{VERSION});
    try w.print("\"width\":{d},", .{@as(i64, @intFromFloat(d.width))});
    try w.print("\"height\":{d},", .{@as(i64, @intFromFloat(d.height))});
    try w.writeAll("\"primitives\":[");

    for (d.primitives.items, 0..) |prim, i| {
        if (i > 0) try w.writeByte(',');
        try writePrimitive(w, prim);
    }

    try w.writeAll("]}");
    return buf.toOwnedSlice();
}

fn writePrimitive(w: anytype, prim: DrawingPrimitive) !void {
    switch (prim) {
        .rect => |r| {
            try w.print("{{\"type\":\"rect\",\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}", .{
                @as(i64, @intFromFloat(r.x)),
                @as(i64, @intFromFloat(r.y)),
                @as(i64, @intFromFloat(r.width)),
                @as(i64, @intFromFloat(r.height)),
            });
            if (r.corner_radius > 0) try w.print(",\"corner_radius\":{d}", .{@as(i64, @intFromFloat(r.corner_radius))});
            try w.writeByte('}');
        },
        .circle => |c| {
            try w.print("{{\"type\":\"circle\",\"cx\":{d},\"cy\":{d},\"r\":{d}}}", .{
                @as(i64, @intFromFloat(c.cx)),
                @as(i64, @intFromFloat(c.cy)),
                @as(i64, @intFromFloat(c.radius)),
            });
        },
        .ellipse => |e| {
            try w.print("{{\"type\":\"ellipse\",\"cx\":{d},\"cy\":{d},\"rx\":{d},\"ry\":{d}}}", .{
                @as(i64, @intFromFloat(e.cx)),
                @as(i64, @intFromFloat(e.cy)),
                @as(i64, @intFromFloat(e.rx)),
                @as(i64, @intFromFloat(e.ry)),
            });
        },
        .text => |t| {
            try w.writeAll("{\"type\":\"text\",");
            try w.print("\"x\":{d},\"y\":{d},", .{
                @as(i64, @intFromFloat(t.x)),
                @as(i64, @intFromFloat(t.y)),
            });
            try w.writeAll("\"content\":\"");
            try writeJsonEscaped(w, t.content);
            try w.writeAll("\"}");
        },
        .line => |l| {
            try w.print("{{\"type\":\"line\",\"x1\":{d},\"y1\":{d},\"x2\":{d},\"y2\":{d}}}", .{
                @as(i64, @intFromFloat(l.x1)),
                @as(i64, @intFromFloat(l.y1)),
                @as(i64, @intFromFloat(l.x2)),
                @as(i64, @intFromFloat(l.y2)),
            });
        },
        .polygon => |p| {
            try w.writeAll("{\"type\":\"polygon\",\"points\":[");
            for (p.points, 0..) |pt, i| {
                if (i > 0) try w.writeByte(',');
                try w.print("[{d},{d}]", .{
                    @as(i64, @intFromFloat(pt.x)),
                    @as(i64, @intFromFloat(pt.y)),
                });
            }
            try w.writeAll("]}");
        },
        .path => |pa| {
            try w.writeAll("{\"type\":\"path\",\"points\":[");
            for (pa.points, 0..) |pt, i| {
                if (i > 0) try w.writeByte(',');
                try w.print("[{d},{d}]", .{
                    @as(i64, @intFromFloat(pt.x)),
                    @as(i64, @intFromFloat(pt.y)),
                });
            }
            try w.writeAll("]}");
        },
        .group => |g| {
            try w.writeAll("{\"type\":\"group\",\"children\":[");
            for (g.children, 0..) |child, i| {
                if (i > 0) try w.writeByte(',');
                try writePrimitive(w, child);
            }
            try w.writeAll("]}");
        },
        .arc => |a| {
            try w.print("{{\"type\":\"arc\",\"cx\":{d},\"cy\":{d},\"r\":{d}}}", .{
                @as(i64, @intFromFloat(a.cx)),
                @as(i64, @intFromFloat(a.cy)),
                @as(i64, @intFromFloat(a.radius)),
            });
        },
    }
}

fn writeJsonEscaped(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            else => try w.writeByte(c),
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 5: Commit**

```
feat: add JSON DrawingIR serializer (schema v2.0)

Serializes DrawingIR primitives as JSON objects with type, position,
and dimension fields. Schema v2.0 alongside existing v1.2 LayoutIR.
```

---

## Task 10: Preset configs

Add diagram-type presets that combine node shapes, edge decorators, and subgraph styles.

**Files:**
- Modify: `src/presets.zig`

- [ ] **Step 1: Write failing tests for new presets**

Add to bottom of `src/presets.zig`:

```zig
test "preset: flowchart uses rounded_rect shape" {
    const config = diagram.flowchart();
    try std.testing.expectEqual(NodeShape.rounded_rect, config.default_node_shape);
}

test "preset: er_diagram uses crow_foot markers" {
    const config = diagram.er_diagram();
    try std.testing.expectEqual(MarkerType.crow_foot_many, config.default_end_marker);
}

test "preset: state_diagram uses double_circle for start" {
    const config = diagram.state_diagram();
    try std.testing.expectEqual(NodeShape.double_circle, config.start_node_shape);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `zig build test 2>&1 | head -20`
Expected: FAIL — `diagram` not defined

- [ ] **Step 3: Implement diagram presets**

Add to `src/presets.zig`:

```zig
const graph_mod = @import("core/graph.zig");
const NodeShape = graph_mod.NodeShape;
const MarkerType = graph_mod.MarkerType;
const SubgraphStyleKind = graph_mod.SubgraphStyleKind;

/// Diagram-type presets for common diagram patterns.
/// These configure default node shapes, edge styles, and subgraph appearance.
pub const DiagramConfig = struct {
    default_node_shape: NodeShape = .rect,
    start_node_shape: NodeShape = .rect,
    end_node_shape: NodeShape = .rect,
    default_start_marker: MarkerType = .none,
    default_end_marker: MarkerType = .arrow,
    default_subgraph_style: SubgraphStyleKind = .default,
};

pub const diagram = struct {
    pub fn flowchart() DiagramConfig {
        return .{
            .default_node_shape = .rounded_rect,
            .default_end_marker = .arrow,
        };
    }

    pub fn er_diagram() DiagramConfig {
        return .{
            .default_node_shape = .rect,
            .default_end_marker = .crow_foot_many,
        };
    }

    pub fn class_diagram() DiagramConfig {
        return .{
            .default_node_shape = .rect,
            .default_end_marker = .hollow_arrow,
        };
    }

    pub fn state_diagram() DiagramConfig {
        return .{
            .start_node_shape = .double_circle,
            .end_node_shape = .double_circle,
            .default_end_marker = .arrow,
        };
    }

    pub fn network() DiagramConfig {
        return .{
            .default_node_shape = .rect,
            .default_subgraph_style = .cloud,
            .default_end_marker = .none,
        };
    }

    pub fn c4_context() DiagramConfig {
        return .{
            .default_node_shape = .rounded_rect,
            .default_subgraph_style = .system,
            .default_end_marker = .arrow,
        };
    }

    pub fn c4_container() DiagramConfig {
        return .{
            .default_node_shape = .rounded_rect,
            .default_subgraph_style = .container,
            .default_end_marker = .arrow,
        };
    }

    pub fn c4_component() DiagramConfig {
        return .{
            .default_node_shape = .rounded_rect,
            .default_subgraph_style = .component,
            .default_end_marker = .arrow,
        };
    }
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 5: Commit**

```
feat: add diagram-type presets (flowchart, ER, class, state, network, C4)

DiagramConfig bundles default node shape, edge markers, and subgraph
style for common diagram patterns.
```

---

## Task 11: Sequence diagram

First Phase 2 primitive — the most commonly requested diagram type after flowcharts.

**Files:**
- Create: `src/primitives/sequence/model.zig`
- Create: `src/primitives/sequence/layout.zig`
- Create: `src/primitives/sequence/ir.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Write failing tests for sequence model**

Create `src/primitives/sequence/model.zig`:

```zig
//! Sequence diagram data model.
//!
//! Actors, messages, and fragments for interaction diagrams.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ActorId = usize;
pub const MessageId = usize;

pub const ActorType = enum { participant, actor, database, queue, boundary };

pub const MessageStyle = enum { sync, async_msg, @"return", create, destroy };

pub const FragmentKind = enum { loop, alt, opt, par, @"break", critical, ref };

pub const ActorOptions = struct {
    actor_type: ActorType = .participant,
};

pub const MessageOptions = struct {
    style: MessageStyle = .sync,
    activate: bool = false,
    deactivate: bool = false,
};

pub const Actor = struct {
    id: ActorId,
    name: []const u8,
    actor_type: ActorType,
};

pub const Message = struct {
    id: MessageId,
    from: ActorId,
    to: ActorId,
    text: []const u8,
    style: MessageStyle,
    activate: bool,
    deactivate: bool,
};

pub const Fragment = struct {
    kind: FragmentKind,
    label: []const u8,
    start_message: MessageId,
    end_message: MessageId,
};

pub const Sequence = struct {
    actors: std.ArrayListUnmanaged(Actor),
    messages: std.ArrayListUnmanaged(Message),
    fragments: std.ArrayListUnmanaged(Fragment),
    allocator: Allocator,
    next_actor_id: ActorId,
    next_message_id: MessageId,

    pub fn init(allocator: Allocator) Sequence {
        return .{
            .actors = .{},
            .messages = .{},
            .fragments = .{},
            .allocator = allocator,
            .next_actor_id = 0,
            .next_message_id = 0,
        };
    }

    pub fn deinit(self: *Sequence) void {
        self.actors.deinit(self.allocator);
        self.messages.deinit(self.allocator);
        self.fragments.deinit(self.allocator);
    }

    pub fn addActor(self: *Sequence, name: []const u8, opts: ActorOptions) !ActorId {
        const id = self.next_actor_id;
        self.next_actor_id += 1;
        try self.actors.append(self.allocator, .{
            .id = id,
            .name = name,
            .actor_type = opts.actor_type,
        });
        return id;
    }

    pub fn addMessage(self: *Sequence, from: ActorId, to: ActorId, text: []const u8, opts: MessageOptions) !MessageId {
        const id = self.next_message_id;
        self.next_message_id += 1;
        try self.messages.append(self.allocator, .{
            .id = id,
            .from = from,
            .to = to,
            .text = text,
            .style = opts.style,
            .activate = opts.activate,
            .deactivate = opts.deactivate,
        });
        return id;
    }

    pub fn addFragment(self: *Sequence, kind: FragmentKind, start_msg: MessageId, end_msg: MessageId, label: []const u8) !void {
        try self.fragments.append(self.allocator, .{
            .kind = kind,
            .label = label,
            .start_message = start_msg,
            .end_message = end_msg,
        });
    }
};

test "sequence: create actors" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{ .actor_type = .database });

    try std.testing.expectEqual(@as(ActorId, 0), a);
    try std.testing.expectEqual(@as(ActorId, 1), b);
    try std.testing.expectEqual(@as(usize, 2), seq.actors.items.len);
    try std.testing.expectEqualStrings("Server", seq.actors.items[1].name);
    try std.testing.expectEqual(ActorType.database, seq.actors.items[1].actor_type);
}

test "sequence: add messages" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{});

    const m1 = try seq.addMessage(a, b, "request", .{});
    const m2 = try seq.addMessage(b, a, "response", .{ .style = .@"return" });

    try std.testing.expectEqual(@as(MessageId, 0), m1);
    try std.testing.expectEqual(@as(MessageId, 1), m2);
    try std.testing.expectEqual(@as(usize, 2), seq.messages.items.len);
}

test "sequence: add fragment" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("A", .{});
    const b = try seq.addActor("B", .{});

    const m1 = try seq.addMessage(a, b, "ping", .{});
    const m2 = try seq.addMessage(b, a, "pong", .{});

    try seq.addFragment(.loop, m1, m2, "retry 3x");

    try std.testing.expectEqual(@as(usize, 1), seq.fragments.items.len);
    try std.testing.expectEqual(FragmentKind.loop, seq.fragments.items[0].kind);
}
```

- [ ] **Step 2: Run test to verify it passes (model is self-contained)**

Run: `zig build test 2>&1 | head -20`
Expected: PASS

- [ ] **Step 3: Create layout algorithm**

Create `src/primitives/sequence/layout.zig`:

```zig
//! Sequence diagram layout algorithm.
//!
//! Places actors left-to-right, messages top-to-bottom.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Sequence = model.Sequence;

pub const SequenceLayout = struct {
    actor_positions: []f64,   // x center per actor
    message_ys: []f64,        // y per message
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

    // Actors should be evenly spaced
    try std.testing.expect(result.actor_positions[1] > result.actor_positions[0]);
    try std.testing.expect(result.actor_positions[2] > result.actor_positions[1]);
    // Spacing should be equal
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

    // Messages should be top-to-bottom with equal spacing
    try std.testing.expect(result.message_ys[1] > result.message_ys[0]);
}
```

- [ ] **Step 4: Create IR conversion**

Create `src/primitives/sequence/ir.zig`:

```zig
//! SequenceIR → DrawingIR conversion.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Sequence = model.Sequence;
const layout_mod = @import("layout.zig");
const SequenceLayout = layout_mod.SequenceLayout;
const layoutSequence = layout_mod.layoutSequence;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

/// Lay out a sequence diagram and convert to DrawingIR.
pub fn toDrawing(seq: *const Sequence, allocator: Allocator, config: LayoutConfig) !Drawing {
    var sl = try layoutSequence(seq, allocator, config);
    defer sl.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(sl.total_width, sl.total_height);

    // Actor boxes at top
    for (seq.actors.items, 0..) |actor, i| {
        const cx = sl.actor_positions[i];
        const bw = config.actor_box_width;
        const bh = config.actor_box_height;

        try d.addPrimitive(.{ .rect = .{
            .x = cx - bw / 2,
            .y = config.margin,
            .width = bw,
            .height = bh,
        } });
        try d.addPrimitive(.{ .text = .{
            .x = cx,
            .y = config.margin + bh / 2,
            .content = actor.name,
            .alignment = .center,
        } });

        // Lifeline (dashed vertical line from bottom of box to diagram bottom)
        try d.addPrimitive(.{ .line = .{
            .x1 = cx,
            .y1 = config.margin + bh,
            .x2 = cx,
            .y2 = sl.total_height - config.margin,
            .style = .dashed,
        } });
    }

    // Messages as horizontal arrows
    for (seq.messages.items, 0..) |msg, i| {
        const from_x = sl.actor_positions[msg.from];
        const to_x = sl.actor_positions[msg.to];
        const y = sl.message_ys[i];

        const marker: drawing.MarkerType = switch (msg.style) {
            .sync => .arrow,
            .async_msg => .hollow_arrow,
            .@"return" => .arrow,
            .create, .destroy => .arrow,
        };
        const line_style: drawing.BorderStyle = if (msg.style == .@"return") .dashed else .solid;

        try d.addPrimitive(.{ .line = .{
            .x1 = from_x,
            .y1 = y,
            .x2 = to_x,
            .y2 = y,
            .end_marker = marker,
            .style = line_style,
        } });

        // Message label above the arrow
        const label_x = (from_x + to_x) / 2;
        try d.addPrimitive(.{ .text = .{
            .x = label_x,
            .y = y - 5,
            .content = msg.text,
            .alignment = .center,
            .font_size = 12,
        } });
    }

    // Fragments as bordered rectangles
    for (seq.fragments.items) |frag| {
        if (frag.start_message >= sl.message_ys.len or frag.end_message >= sl.message_ys.len) continue;
        const top_y = sl.message_ys[frag.start_message] - 15;
        const bot_y = sl.message_ys[frag.end_message] + 15;

        try d.addPrimitive(.{ .rect = .{
            .x = config.margin,
            .y = top_y,
            .width = sl.total_width - 2 * config.margin,
            .height = bot_y - top_y,
            .border_style = .dashed,
        } });
        try d.addPrimitive(.{ .text = .{
            .x = config.margin + 5,
            .y = top_y + 12,
            .content = frag.label,
            .alignment = .left,
            .style = .{ .bold = true },
            .font_size = 11,
        } });
    }

    return d;
}

test "sequence ir: basic sequence to drawing" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{});
    _ = try seq.addMessage(a, b, "GET /api", .{});
    _ = try seq.addMessage(b, a, "200 OK", .{ .style = .@"return" });

    var d = try toDrawing(&seq, allocator, .{});
    defer d.deinit();

    // Should have: 2 actor boxes + 2 actor labels + 2 lifelines + 2 message lines + 2 message labels = 10
    try std.testing.expect(d.primitives.items.len >= 10);
    try std.testing.expect(d.width > 0);
    try std.testing.expect(d.height > 0);
}

test "sequence ir: empty sequence" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    var d = try toDrawing(&seq, allocator, .{});
    defer d.deinit();

    try std.testing.expectEqual(@as(usize, 0), d.primitives.items.len);
}
```

- [ ] **Step 5: Add re-export to root.zig**

Add to `src/root.zig` rendering section:

```zig
/// Sequence diagram primitive
pub const sequence = struct {
    pub const model = @import("primitives/sequence/model.zig");
    pub const layout = @import("primitives/sequence/layout.zig");
    pub const ir = @import("primitives/sequence/ir.zig");
    pub const Sequence = model.Sequence;
    pub const toDrawing = ir.toDrawing;
};
```

- [ ] **Step 6: Run all tests**

Run: `zig build test 2>&1 | head -30`
Expected: PASS

- [ ] **Step 7: Commit**

```
feat: add sequence diagram primitive

Sequence model (actors, messages, fragments), layout algorithm
(actors left-to-right, messages top-to-bottom), and DrawingIR
conversion with lifelines, message arrows, and fragment boxes.
```

---

## Task 12: Gantt chart

**Files:**
- Create: `src/primitives/gantt/model.zig`
- Create: `src/primitives/gantt/layout.zig`
- Create: `src/primitives/gantt/ir.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Create Gantt model with tests**

Create `src/primitives/gantt/model.zig`:

```zig
//! Gantt chart data model.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TaskId = usize;
pub const SectionId = usize;
pub const MilestoneId = usize;

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn daysSinceEpoch(self: Date) i32 {
        // Simplified: days from year 0, ignoring leap year edge cases for layout purposes
        const y: i32 = @intCast(self.year);
        const m: i32 = @intCast(self.month);
        const d: i32 = @intCast(self.day);
        return y * 365 + (y / 4) + (m - 1) * 30 + d;
    }

    pub fn daysBetween(a: Date, b: Date) i32 {
        return b.daysSinceEpoch() - a.daysSinceEpoch();
    }
};

pub const TaskOptions = struct {
    start: ?Date = null,
    after: ?TaskId = null,
    duration_days: u32 = 1,
    progress: u8 = 0,
    is_critical: bool = false,
    section: ?SectionId = null,
};

pub const MilestoneOptions = struct {
    date: ?Date = null,
    after: ?TaskId = null,
};

pub const Section = struct {
    id: SectionId,
    name: []const u8,
};

pub const Task = struct {
    id: TaskId,
    name: []const u8,
    start: Date,
    duration_days: u32,
    progress: u8,
    is_critical: bool,
    section: ?SectionId,
    after: ?TaskId,
};

pub const Milestone = struct {
    id: MilestoneId,
    name: []const u8,
    date: Date,
};

pub const GanttOptions = struct {
    title: ?[]const u8 = null,
    default_start: Date = .{ .year = 2026, .month = 1, .day = 1 },
};

pub const Gantt = struct {
    title: ?[]const u8,
    default_start: Date,
    sections: std.ArrayListUnmanaged(Section),
    tasks: std.ArrayListUnmanaged(Task),
    milestones: std.ArrayListUnmanaged(Milestone),
    allocator: Allocator,
    next_task_id: TaskId,
    next_section_id: SectionId,
    next_milestone_id: MilestoneId,

    pub fn init(allocator: Allocator, opts: GanttOptions) Gantt {
        return .{
            .title = opts.title,
            .default_start = opts.default_start,
            .sections = .{},
            .tasks = .{},
            .milestones = .{},
            .allocator = allocator,
            .next_task_id = 0,
            .next_section_id = 0,
            .next_milestone_id = 0,
        };
    }

    pub fn deinit(self: *Gantt) void {
        self.sections.deinit(self.allocator);
        self.tasks.deinit(self.allocator);
        self.milestones.deinit(self.allocator);
    }

    pub fn addSection(self: *Gantt, name: []const u8) !SectionId {
        const id = self.next_section_id;
        self.next_section_id += 1;
        try self.sections.append(self.allocator, .{ .id = id, .name = name });
        return id;
    }

    pub fn addTask(self: *Gantt, name: []const u8, opts: TaskOptions) !TaskId {
        const id = self.next_task_id;
        self.next_task_id += 1;

        const start = opts.start orelse blk: {
            if (opts.after) |after_id| {
                // Find the task and compute end date
                for (self.tasks.items) |t| {
                    if (t.id == after_id) {
                        var end = t.start;
                        end.day += @intCast(t.duration_days);
                        // Simplified: no month overflow handling for layout
                        break :blk end;
                    }
                }
            }
            break :blk self.default_start;
        };

        try self.tasks.append(self.allocator, .{
            .id = id,
            .name = name,
            .start = start,
            .duration_days = opts.duration_days,
            .progress = opts.progress,
            .is_critical = opts.is_critical,
            .section = opts.section,
            .after = opts.after,
        });
        return id;
    }

    pub fn addMilestone(self: *Gantt, name: []const u8, opts: MilestoneOptions) !MilestoneId {
        const id = self.next_milestone_id;
        self.next_milestone_id += 1;

        const date = opts.date orelse blk: {
            if (opts.after) |after_id| {
                for (self.tasks.items) |t| {
                    if (t.id == after_id) {
                        var end = t.start;
                        end.day += @intCast(t.duration_days);
                        break :blk end;
                    }
                }
            }
            break :blk self.default_start;
        };

        try self.milestones.append(self.allocator, .{ .id = id, .name = name, .date = date });
        return id;
    }
};

test "gantt: create tasks with dependencies" {
    const allocator = std.testing.allocator;
    var gantt = Gantt.init(allocator, .{ .title = "Sprint 1" });
    defer gantt.deinit();

    const t1 = try gantt.addTask("Design", .{
        .start = .{ .year = 2026, .month = 1, .day = 1 },
        .duration_days = 5,
    });
    const t2 = try gantt.addTask("Implement", .{
        .after = t1,
        .duration_days = 10,
    });

    try std.testing.expectEqual(@as(TaskId, 0), t1);
    try std.testing.expectEqual(@as(TaskId, 1), t2);
    // t2 should start after t1 ends
    try std.testing.expectEqual(@as(u8, 6), gantt.tasks.items[1].start.day);
}

test "gantt: add milestone after task" {
    const allocator = std.testing.allocator;
    var gantt = Gantt.init(allocator, .{});
    defer gantt.deinit();

    const t1 = try gantt.addTask("Work", .{
        .start = .{ .year = 2026, .month = 1, .day = 1 },
        .duration_days = 10,
    });
    _ = try gantt.addMilestone("MVP", .{ .after = t1 });

    try std.testing.expectEqual(@as(u8, 11), gantt.milestones.items[0].date.day);
}

test "gantt: sections group tasks" {
    const allocator = std.testing.allocator;
    var gantt = Gantt.init(allocator, .{});
    defer gantt.deinit();

    const s1 = try gantt.addSection("Phase 1");
    _ = try gantt.addTask("Task A", .{ .section = s1, .duration_days = 3 });

    try std.testing.expectEqualStrings("Phase 1", gantt.sections.items[0].name);
    try std.testing.expectEqual(s1, gantt.tasks.items[0].section.?);
}
```

- [ ] **Step 2: Create Gantt layout + IR**

Create `src/primitives/gantt/layout.zig` and `src/primitives/gantt/ir.zig` following the same pattern as sequence — layout computes positions, IR converts to DrawingIR.

Create `src/primitives/gantt/layout.zig`:

```zig
//! Gantt chart layout algorithm.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Gantt = model.Gantt;
const Date = model.Date;

pub const GanttLayout = struct {
    task_ys: []f64,
    total_width: f64,
    total_height: f64,
    min_day: i32,
    max_day: i32,
    day_width: f64,
    allocator: Allocator,

    pub fn deinit(self: *GanttLayout) void {
        self.allocator.free(self.task_ys);
    }
};

pub const LayoutConfig = struct {
    row_height: f64 = 30,
    day_width: f64 = 20,
    label_width: f64 = 120,
    header_height: f64 = 40,
    margin: f64 = 10,
};

pub fn layoutGantt(gantt: *const Gantt, allocator: Allocator, config: LayoutConfig) !GanttLayout {
    const n_tasks = gantt.tasks.items.len;

    var task_ys = try allocator.alloc(f64, n_tasks);
    errdefer allocator.free(task_ys);

    // Find date range
    var min_day: i32 = std.math.maxInt(i32);
    var max_day: i32 = std.math.minInt(i32);
    for (gantt.tasks.items) |t| {
        const start = t.start.daysSinceEpoch();
        const end = start + @as(i32, @intCast(t.duration_days));
        if (start < min_day) min_day = start;
        if (end > max_day) max_day = end;
    }
    for (gantt.milestones.items) |m| {
        const d = m.date.daysSinceEpoch();
        if (d < min_day) min_day = d;
        if (d > max_day) max_day = d;
    }
    if (min_day > max_day) {
        min_day = 0;
        max_day = 1;
    }

    // Task rows
    for (0..n_tasks) |i| {
        const fi: f64 = @floatFromInt(i);
        task_ys[i] = config.header_height + config.margin + fi * config.row_height;
    }

    const day_span: f64 = @floatFromInt(max_day - min_day);
    const chart_width = config.label_width + day_span * config.day_width + config.margin;
    const n_tasks_f: f64 = @floatFromInt(n_tasks);
    const chart_height = config.header_height + n_tasks_f * config.row_height + config.margin * 2;

    return .{
        .task_ys = task_ys,
        .total_width = chart_width,
        .total_height = chart_height,
        .min_day = min_day,
        .max_day = max_day,
        .day_width = config.day_width,
        .allocator = allocator,
    };
}

test "gantt layout: task rows stacked vertically" {
    const allocator = std.testing.allocator;
    var gantt = Gantt.init(allocator, .{});
    defer gantt.deinit();

    _ = try gantt.addTask("A", .{ .start = .{ .year = 2026, .month = 1, .day = 1 }, .duration_days = 3 });
    _ = try gantt.addTask("B", .{ .start = .{ .year = 2026, .month = 1, .day = 2 }, .duration_days = 5 });

    var result = try layoutGantt(&gantt, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.task_ys[1] > result.task_ys[0]);
    try std.testing.expect(result.total_width > 0);
}
```

Create `src/primitives/gantt/ir.zig`:

```zig
//! GanttIR → DrawingIR conversion.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Gantt = model.Gantt;
const layout_mod = @import("layout.zig");
const layoutGantt = layout_mod.layoutGantt;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

pub fn toDrawing(gantt: *const Gantt, allocator: Allocator, config: LayoutConfig) !Drawing {
    var gl = try layoutGantt(gantt, allocator, config);
    defer gl.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(gl.total_width, gl.total_height);

    // Task bars
    for (gantt.tasks.items, 0..) |task, i| {
        const y = gl.task_ys[i];
        const start_day = task.start.daysSinceEpoch();
        const x: f64 = config.label_width + @as(f64, @floatFromInt(start_day - gl.min_day)) * gl.day_width;
        const w: f64 = @as(f64, @floatFromInt(task.duration_days)) * gl.day_width;

        // Task label
        try d.addPrimitive(.{ .text = .{
            .x = config.margin,
            .y = y + config.row_height / 2,
            .content = task.name,
            .alignment = .left,
        } });

        // Task bar
        try d.addPrimitive(.{ .rect = .{
            .x = x,
            .y = y + 5,
            .width = w,
            .height = config.row_height - 10,
            .corner_radius = 3,
            .fill = if (task.is_critical) .{ .solid = .{ .r = 220, .g = 50, .b = 50 } } else .{ .solid = .{ .r = 70, .g = 130, .b = 220 } },
        } });

        // Progress fill
        if (task.progress > 0) {
            const progress_w = w * @as(f64, @floatFromInt(task.progress)) / 100.0;
            try d.addPrimitive(.{ .rect = .{
                .x = x,
                .y = y + 5,
                .width = progress_w,
                .height = config.row_height - 10,
                .corner_radius = 3,
                .fill = .{ .solid = .{ .r = 50, .g = 180, .b = 50 } },
                .border_style = .none,
            } });
        }
    }

    // Milestones as diamonds
    for (gantt.milestones.items) |ms| {
        const day = ms.date.daysSinceEpoch();
        const x: f64 = config.label_width + @as(f64, @floatFromInt(day - gl.min_day)) * gl.day_width;
        const n_tasks_f: f64 = @floatFromInt(gantt.tasks.items.len);
        const y: f64 = config.header_height + n_tasks_f * config.row_height;

        // Diamond shape for milestone
        const size: f64 = 8;
        const pts = [_]drawing.Point{
            .{ .x = x, .y = y - size },
            .{ .x = x + size, .y = y },
            .{ .x = x, .y = y + size },
            .{ .x = x - size, .y = y },
        };
        _ = pts;
        // Note: polygon needs heap-allocated points for Drawing — use circle as simpler marker
        try d.addPrimitive(.{ .circle = .{
            .cx = x,
            .cy = y,
            .radius = 5,
            .fill = .{ .solid = .{ .r = 255, .g = 165, .b = 0 } },
        } });
        try d.addPrimitive(.{ .text = .{
            .x = x + 10,
            .y = y,
            .content = ms.name,
            .alignment = .left,
            .font_size = 11,
        } });
    }

    return d;
}

test "gantt ir: basic chart to drawing" {
    const allocator = std.testing.allocator;
    var gantt = Gantt.init(allocator, .{ .title = "Sprint" });
    defer gantt.deinit();

    _ = try gantt.addTask("Design", .{
        .start = .{ .year = 2026, .month = 1, .day = 1 },
        .duration_days = 5,
    });
    _ = try gantt.addTask("Build", .{
        .start = .{ .year = 2026, .month = 1, .day = 3 },
        .duration_days = 8,
    });

    var d = try toDrawing(&gantt, allocator, .{});
    defer d.deinit();

    // 2 task labels + 2 task bars = 4 minimum
    try std.testing.expect(d.primitives.items.len >= 4);
    try std.testing.expect(d.width > 0);
}
```

- [ ] **Step 3: Add re-export to root.zig**

```zig
/// Gantt chart primitive
pub const gantt = struct {
    pub const model = @import("primitives/gantt/model.zig");
    pub const layout = @import("primitives/gantt/layout.zig");
    pub const ir = @import("primitives/gantt/ir.zig");
    pub const Gantt = model.Gantt;
    pub const toDrawing = ir.toDrawing;
};
```

- [ ] **Step 4: Run all tests**

Run: `zig build test 2>&1 | head -30`
Expected: PASS

- [ ] **Step 5: Commit**

```
feat: add Gantt chart primitive

Gantt model (tasks, milestones, sections, dependencies), time-axis
layout, and DrawingIR conversion with task bars, progress fills,
and milestone markers.
```

---

## Task 13: Mindmap

**Files:**
- Create: `src/primitives/mindmap/model.zig`
- Create: `src/primitives/mindmap/layout.zig`
- Create: `src/primitives/mindmap/ir.zig`
- Modify: `src/root.zig` (add re-export)

- [ ] **Step 1: Create mindmap model with tests**

Create `src/primitives/mindmap/model.zig`:

```zig
//! Mindmap data model — radial tree from center.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MindNodeId = usize;

pub const MindShape = enum { rounded_rect, rect, circle, cloud, hexagon };

pub const MindNodeOptions = struct {
    shape: MindShape = .rounded_rect,
};

pub const MindNode = struct {
    id: MindNodeId,
    text: []const u8,
    shape: MindShape,
    parent: ?MindNodeId,
    children: std.ArrayListUnmanaged(MindNodeId),
};

pub const Mindmap = struct {
    nodes: std.ArrayListUnmanaged(MindNode),
    root: ?MindNodeId,
    allocator: Allocator,
    next_id: MindNodeId,

    pub fn init(allocator: Allocator) Mindmap {
        return .{
            .nodes = .{},
            .root = null,
            .allocator = allocator,
            .next_id = 0,
        };
    }

    pub fn deinit(self: *Mindmap) void {
        for (self.nodes.items) |*n| {
            n.children.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
    }

    pub fn addNode(self: *Mindmap, text: []const u8, opts: MindNodeOptions) !MindNodeId {
        const id = self.next_id;
        self.next_id += 1;
        try self.nodes.append(self.allocator, .{
            .id = id,
            .text = text,
            .shape = opts.shape,
            .parent = null,
            .children = .{},
        });
        return id;
    }

    pub fn addChild(self: *Mindmap, parent: MindNodeId, child: MindNodeId) !void {
        self.nodes.items[child].parent = parent;
        try self.nodes.items[parent].children.append(self.allocator, child);
    }

    pub fn setRoot(self: *Mindmap, node: MindNodeId) void {
        self.root = node;
    }
};

test "mindmap: build tree" {
    const allocator = std.testing.allocator;
    var mm = Mindmap.init(allocator);
    defer mm.deinit();

    const root = try mm.addNode("Central Idea", .{});
    mm.setRoot(root);

    const c1 = try mm.addNode("Branch A", .{});
    const c2 = try mm.addNode("Branch B", .{});
    try mm.addChild(root, c1);
    try mm.addChild(root, c2);

    try std.testing.expectEqual(@as(usize, 3), mm.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 2), mm.nodes.items[0].children.items.len);
    try std.testing.expectEqual(root, mm.nodes.items[1].parent.?);
}
```

- [ ] **Step 2: Create mindmap layout + IR**

Create `src/primitives/mindmap/layout.zig`:

```zig
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
```

Create `src/primitives/mindmap/ir.zig`:

```zig
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
```

- [ ] **Step 3: Add re-export + run tests + commit**

Add to `src/root.zig`:

```zig
pub const mindmap = struct {
    pub const model = @import("primitives/mindmap/model.zig");
    pub const layout = @import("primitives/mindmap/layout.zig");
    pub const ir = @import("primitives/mindmap/ir.zig");
    pub const Mindmap = model.Mindmap;
    pub const toDrawing = ir.toDrawing;
};
```

Run: `zig build test 2>&1 | head -30`

Commit:

```
feat: add mindmap primitive with radial tree layout

Mindmap model (tree of MindNodes), radial layout algorithm (BFS
with angular sector allocation), and DrawingIR conversion.
```

---

## Task 14: Timeline + Git graph

Two smaller primitives bundled together since they follow the established pattern.

**Files:**
- Create: `src/primitives/timeline/model.zig`
- Create: `src/primitives/timeline/layout.zig`
- Create: `src/primitives/timeline/ir.zig`
- Create: `src/primitives/git_graph/model.zig`
- Create: `src/primitives/git_graph/layout.zig`
- Create: `src/primitives/git_graph/ir.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Create Timeline model**

Create `src/primitives/timeline/model.zig`:

```zig
//! Timeline data model — events on a horizontal time axis.

const std = @import("std");
const Allocator = std.mem.Allocator;
const gantt_model = @import("../gantt/model.zig");
pub const Date = gantt_model.Date;

pub const EventOptions = struct {
    description: ?[]const u8 = null,
    group: ?[]const u8 = null,
};

pub const Event = struct {
    title: []const u8,
    date: Date,
    description: ?[]const u8,
    group: ?[]const u8,
};

pub const Period = struct {
    title: []const u8,
    start: Date,
    end: Date,
};

pub const TimelineOptions = struct {
    title: ?[]const u8 = null,
};

pub const Timeline = struct {
    title: ?[]const u8,
    events: std.ArrayListUnmanaged(Event),
    periods: std.ArrayListUnmanaged(Period),
    allocator: Allocator,

    pub fn init(allocator: Allocator, opts: TimelineOptions) Timeline {
        return .{
            .title = opts.title,
            .events = .{},
            .periods = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Timeline) void {
        self.events.deinit(self.allocator);
        self.periods.deinit(self.allocator);
    }

    pub fn addEvent(self: *Timeline, title: []const u8, date: Date, opts: EventOptions) !void {
        try self.events.append(self.allocator, .{
            .title = title,
            .date = date,
            .description = opts.description,
            .group = opts.group,
        });
    }

    pub fn addPeriod(self: *Timeline, title: []const u8, start: Date, end: Date) !void {
        try self.periods.append(self.allocator, .{ .title = title, .start = start, .end = end });
    }
};

test "timeline: add events and periods" {
    const allocator = std.testing.allocator;
    var tl = Timeline.init(allocator, .{ .title = "Project History" });
    defer tl.deinit();

    try tl.addEvent("Launch", .{ .year = 2026, .month = 3, .day = 1 }, .{});
    try tl.addEvent("v2.0", .{ .year = 2026, .month = 6, .day = 15 }, .{ .description = "Major release" });
    try tl.addPeriod("Beta", .{ .year = 2026, .month = 1, .day = 1 }, .{ .year = 2026, .month = 3, .day = 1 });

    try std.testing.expectEqual(@as(usize, 2), tl.events.items.len);
    try std.testing.expectEqual(@as(usize, 1), tl.periods.items.len);
}
```

- [ ] **Step 2: Create Timeline layout + IR**

Create `src/primitives/timeline/layout.zig`:

```zig
//! Timeline layout — horizontal time axis with event markers.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Timeline = model.Timeline;
const Date = model.Date;

pub const LayoutConfig = struct {
    day_width: f64 = 5,
    margin: f64 = 40,
    axis_y: f64 = 100,
    event_height: f64 = 60,
};

pub const TimelineLayout = struct {
    event_xs: []f64,
    min_day: i32,
    total_width: f64,
    total_height: f64,
    allocator: Allocator,

    pub fn deinit(self: *TimelineLayout) void {
        self.allocator.free(self.event_xs);
    }
};

pub fn layoutTimeline(tl: *const Timeline, allocator: Allocator, config: LayoutConfig) !TimelineLayout {
    const n = tl.events.items.len;
    var xs = try allocator.alloc(f64, n);
    errdefer allocator.free(xs);

    var min_day: i32 = std.math.maxInt(i32);
    var max_day: i32 = std.math.minInt(i32);

    for (tl.events.items) |ev| {
        const d = ev.date.daysSinceEpoch();
        if (d < min_day) min_day = d;
        if (d > max_day) max_day = d;
    }
    for (tl.periods.items) |p| {
        const s = p.start.daysSinceEpoch();
        const e = p.end.daysSinceEpoch();
        if (s < min_day) min_day = s;
        if (e > max_day) max_day = e;
    }
    if (min_day > max_day) { min_day = 0; max_day = 1; }

    for (tl.events.items, 0..) |ev, i| {
        const d: f64 = @floatFromInt(ev.date.daysSinceEpoch() - min_day);
        xs[i] = config.margin + d * config.day_width;
    }

    const span: f64 = @floatFromInt(max_day - min_day);

    return .{
        .event_xs = xs,
        .min_day = min_day,
        .total_width = config.margin * 2 + span * config.day_width,
        .total_height = config.axis_y + config.event_height + config.margin,
        .allocator = allocator,
    };
}

test "timeline layout: events positioned on axis" {
    const allocator = std.testing.allocator;
    var tl = Timeline.init(allocator, .{});
    defer tl.deinit();

    try tl.addEvent("A", .{ .year = 2026, .month = 1, .day = 1 }, .{});
    try tl.addEvent("B", .{ .year = 2026, .month = 2, .day = 1 }, .{});

    var result = try layoutTimeline(&tl, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.event_xs[1] > result.event_xs[0]);
}
```

Create `src/primitives/timeline/ir.zig`:

```zig
//! TimelineIR → DrawingIR.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Timeline = model.Timeline;
const layout_mod = @import("layout.zig");
const layoutTimeline = layout_mod.layoutTimeline;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

pub fn toDrawing(tl: *const Timeline, allocator: Allocator, config: LayoutConfig) !Drawing {
    var ll = try layoutTimeline(tl, allocator, config);
    defer ll.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(ll.total_width, ll.total_height);

    // Time axis line
    try d.addPrimitive(.{ .line = .{
        .x1 = config.margin,
        .y1 = config.axis_y,
        .x2 = ll.total_width - config.margin,
        .y2 = config.axis_y,
        .weight = 2,
    } });

    // Events as markers + labels alternating above/below
    for (tl.events.items, 0..) |ev, i| {
        const x = ll.event_xs[i];
        const above = (i % 2 == 0);
        const label_y = if (above) config.axis_y - 30 else config.axis_y + 30;
        const tick_end = if (above) config.axis_y - 10 else config.axis_y + 10;

        // Tick mark
        try d.addPrimitive(.{ .line = .{ .x1 = x, .y1 = config.axis_y, .x2 = x, .y2 = tick_end } });
        // Dot
        try d.addPrimitive(.{ .circle = .{ .cx = x, .cy = config.axis_y, .radius = 4, .fill = .{ .solid = .{ .r = 70, .g = 130, .b = 220 } } } });
        // Label
        try d.addPrimitive(.{ .text = .{ .x = x, .y = label_y, .content = ev.title, .alignment = .center, .font_size = 12 } });
    }

    return d;
}

test "timeline ir: events to drawing" {
    const allocator = std.testing.allocator;
    var tl = Timeline.init(allocator, .{});
    defer tl.deinit();

    try tl.addEvent("Launch", .{ .year = 2026, .month = 3, .day = 1 }, .{});

    var d = try toDrawing(&tl, allocator, .{});
    defer d.deinit();

    // axis line + tick + dot + label = 4 minimum
    try std.testing.expect(d.primitives.items.len >= 4);
}
```

- [ ] **Step 3: Create Git graph model**

Create `src/primitives/git_graph/model.zig`:

```zig
//! Git graph data model — branches, commits, merges.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CommitId = usize;
pub const BranchId = usize;

pub const BranchOptions = struct {
    from_branch: ?BranchId = null,
};

pub const CommitOptions = struct {
    message: ?[]const u8 = null,
    tag: ?[]const u8 = null,
};

pub const Branch = struct {
    id: BranchId,
    name: []const u8,
    from_branch: ?BranchId,
    head: ?CommitId,
};

pub const Commit = struct {
    id: CommitId,
    branch: BranchId,
    message: ?[]const u8,
    tag: ?[]const u8,
    is_merge: bool,
    merge_from: ?BranchId,
};

pub const GitGraph = struct {
    branches: std.ArrayListUnmanaged(Branch),
    commits: std.ArrayListUnmanaged(Commit),
    allocator: Allocator,
    next_commit_id: CommitId,
    next_branch_id: BranchId,

    pub fn init(allocator: Allocator) GitGraph {
        return .{
            .branches = .{},
            .commits = .{},
            .allocator = allocator,
            .next_commit_id = 0,
            .next_branch_id = 0,
        };
    }

    pub fn deinit(self: *GitGraph) void {
        self.branches.deinit(self.allocator);
        self.commits.deinit(self.allocator);
    }

    pub fn addBranch(self: *GitGraph, name: []const u8, opts: BranchOptions) !BranchId {
        const id = self.next_branch_id;
        self.next_branch_id += 1;
        try self.branches.append(self.allocator, .{
            .id = id,
            .name = name,
            .from_branch = opts.from_branch,
            .head = null,
        });
        return id;
    }

    pub fn addCommit(self: *GitGraph, branch: BranchId, opts: CommitOptions) !CommitId {
        const id = self.next_commit_id;
        self.next_commit_id += 1;
        try self.commits.append(self.allocator, .{
            .id = id,
            .branch = branch,
            .message = opts.message,
            .tag = opts.tag,
            .is_merge = false,
            .merge_from = null,
        });
        self.branches.items[branch].head = id;
        return id;
    }

    pub fn merge(self: *GitGraph, from: BranchId, into: BranchId, opts: CommitOptions) !CommitId {
        const id = self.next_commit_id;
        self.next_commit_id += 1;
        try self.commits.append(self.allocator, .{
            .id = id,
            .branch = into,
            .message = opts.message,
            .tag = opts.tag,
            .is_merge = true,
            .merge_from = from,
        });
        self.branches.items[into].head = id;
        return id;
    }
};

test "git graph: branches and commits" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main, .{ .message = "initial" });
    _ = try gg.addCommit(main, .{ .message = "add feature" });

    const feat = try gg.addBranch("feature", .{ .from_branch = main });
    _ = try gg.addCommit(feat, .{ .message = "wip" });

    try std.testing.expectEqual(@as(usize, 2), gg.branches.items.len);
    try std.testing.expectEqual(@as(usize, 3), gg.commits.items.len);
}

test "git graph: merge creates commit on target branch" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main, .{ .message = "init" });
    const feat = try gg.addBranch("feature", .{ .from_branch = main });
    _ = try gg.addCommit(feat, .{ .message = "work" });

    const merge_id = try gg.merge(feat, main, .{ .message = "merge feature" });

    const commit = gg.commits.items[merge_id];
    try std.testing.expect(commit.is_merge);
    try std.testing.expectEqual(main, commit.branch);
    try std.testing.expectEqual(feat, commit.merge_from.?);
}
```

- [ ] **Step 4: Create Git graph layout + IR**

Create `src/primitives/git_graph/layout.zig`:

```zig
//! Git graph lane-based layout.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const GitGraph = model.GitGraph;

pub const LayoutConfig = struct {
    lane_width: f64 = 40,
    commit_spacing: f64 = 30,
    margin: f64 = 20,
    commit_radius: f64 = 5,
};

pub const GitGraphLayout = struct {
    commit_positions: []Position,
    branch_lanes: []usize,
    total_width: f64,
    total_height: f64,
    allocator: Allocator,

    pub const Position = struct { x: f64, y: f64 };

    pub fn deinit(self: *GitGraphLayout) void {
        self.allocator.free(self.commit_positions);
        self.allocator.free(self.branch_lanes);
    }
};

pub fn layoutGitGraph(gg: *const GitGraph, allocator: Allocator, config: LayoutConfig) !GitGraphLayout {
    const n_commits = gg.commits.items.len;
    const n_branches = gg.branches.items.len;

    var positions = try allocator.alloc(GitGraphLayout.Position, n_commits);
    errdefer allocator.free(positions);

    var lanes = try allocator.alloc(usize, n_branches);
    errdefer allocator.free(lanes);

    // Assign each branch a lane (column) in creation order
    for (0..n_branches) |i| {
        lanes[i] = i;
    }

    // Commits placed top-to-bottom in chronological order
    for (0..n_commits) |i| {
        const commit = gg.commits.items[i];
        const lane = lanes[commit.branch];
        const fi: f64 = @floatFromInt(i);
        const lane_f: f64 = @floatFromInt(lane);
        positions[i] = .{
            .x = config.margin + lane_f * config.lane_width,
            .y = config.margin + fi * config.commit_spacing,
        };
    }

    const n_lanes_f: f64 = @floatFromInt(n_branches);
    const n_commits_f: f64 = @floatFromInt(n_commits);

    return .{
        .commit_positions = positions,
        .branch_lanes = lanes,
        .total_width = config.margin * 2 + n_lanes_f * config.lane_width,
        .total_height = config.margin * 2 + n_commits_f * config.commit_spacing,
        .allocator = allocator,
    };
}

test "git graph layout: commits on lanes" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main, .{});
    const feat = try gg.addBranch("feat", .{});
    _ = try gg.addCommit(feat, .{});

    var result = try layoutGitGraph(&gg, allocator, .{});
    defer result.deinit();

    // Commits on different branches should have different x positions
    try std.testing.expect(result.commit_positions[0].x != result.commit_positions[1].x);
}
```

Create `src/primitives/git_graph/ir.zig`:

```zig
//! GitGraphIR → DrawingIR.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const GitGraph = model.GitGraph;
const layout_mod = @import("layout.zig");
const layoutGitGraph = layout_mod.layoutGitGraph;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

pub fn toDrawing(gg: *const GitGraph, allocator: Allocator, config: LayoutConfig) !Drawing {
    var gl = try layoutGitGraph(gg, allocator, config);
    defer gl.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(gl.total_width, gl.total_height);

    // Branch lane lines
    for (0..gg.branches.items.len) |bi| {
        const lane_f: f64 = @floatFromInt(gl.branch_lanes[bi]);
        const x = config.margin + lane_f * config.lane_width;
        try d.addPrimitive(.{ .line = .{
            .x1 = x,
            .y1 = config.margin,
            .x2 = x,
            .y2 = gl.total_height - config.margin,
            .style = .solid,
        } });
    }

    // Commits as dots + labels
    for (gg.commits.items, 0..) |commit, i| {
        const pos = gl.commit_positions[i];

        // Commit dot
        try d.addPrimitive(.{ .circle = .{
            .cx = pos.x,
            .cy = pos.y,
            .radius = config.commit_radius,
            .fill = .{ .solid = .{ .r = 70, .g = 130, .b = 220 } },
        } });

        // Message label
        if (commit.message) |msg| {
            const n_lanes_f: f64 = @floatFromInt(gg.branches.items.len);
            try d.addPrimitive(.{ .text = .{
                .x = config.margin + n_lanes_f * config.lane_width + 10,
                .y = pos.y,
                .content = msg,
                .alignment = .left,
                .font_size = 11,
            } });
        }

        // Merge line
        if (commit.is_merge) {
            if (commit.merge_from) |from_branch| {
                const from_lane: f64 = @floatFromInt(gl.branch_lanes[from_branch]);
                const from_x = config.margin + from_lane * config.lane_width;
                try d.addPrimitive(.{ .line = .{
                    .x1 = from_x,
                    .y1 = pos.y - config.commit_spacing / 2,
                    .x2 = pos.x,
                    .y2 = pos.y,
                    .end_marker = .arrow,
                } });
            }
        }

        // Tag
        if (commit.tag) |tag| {
            try d.addPrimitive(.{ .text = .{
                .x = pos.x + 15,
                .y = pos.y - 8,
                .content = tag,
                .style = .{ .bold = true },
                .font_size = 10,
            } });
        }
    }

    return d;
}

test "git graph ir: branches and commits to drawing" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main, .{ .message = "init" });
    _ = try gg.addCommit(main, .{ .message = "feat", .tag = "v1.0" });

    var d = try toDrawing(&gg, allocator, .{});
    defer d.deinit();

    // 1 lane line + 2 commit dots + 2 message labels + 1 tag = 6 min
    try std.testing.expect(d.primitives.items.len >= 6);
}
```

- [ ] **Step 5: Add re-exports and run tests**

Add to `src/root.zig`:

```zig
pub const timeline = struct {
    pub const model = @import("primitives/timeline/model.zig");
    pub const layout = @import("primitives/timeline/layout.zig");
    pub const ir = @import("primitives/timeline/ir.zig");
    pub const Timeline = model.Timeline;
    pub const toDrawing = ir.toDrawing;
};

pub const git_graph = struct {
    pub const model = @import("primitives/git_graph/model.zig");
    pub const layout = @import("primitives/git_graph/layout.zig");
    pub const ir = @import("primitives/git_graph/ir.zig");
    pub const GitGraph = model.GitGraph;
    pub const toDrawing = ir.toDrawing;
};
```

Run: `zig build test 2>&1 | head -30`
Expected: PASS

- [ ] **Step 6: Commit**

```
feat: add timeline and git graph primitives

Timeline: events on horizontal time axis with alternating labels.
Git graph: lane-based branch/commit/merge visualization.
Both convert to DrawingIR for terminal/SVG/JSON rendering.
```

---

## Task 15: root.zig refactor + DrawingIR re-exports

Extract layout dispatch from root.zig into layout.zig and add all remaining re-exports.

**Files:**
- Create: `src/layout.zig`
- Modify: `src/root.zig`

- [ ] **Step 1: Create layout.zig with extracted dispatch logic**

Create `src/layout.zig` — move the `layout()`, `layoutSugiyama()`, `layoutFdg()`, and `layoutTyped()` functions from root.zig. Keep the same signatures.

- [ ] **Step 2: Update root.zig to import from layout.zig**

Replace the layout functions in root.zig with:

```zig
const layout_mod = @import("layout.zig");
pub const layout = layout_mod.layout;
pub const layoutTyped = layout_mod.layoutTyped;
```

Add DrawingIR re-exports:

```zig
/// Drawing IR — renderer-agnostic primitives
pub const drawing = @import("drawing/ir.zig");
pub const Drawing = drawing.Drawing;
pub const DrawingPrimitive = drawing.DrawingPrimitive;

/// DrawingIR renderers
pub const drawing_json = @import("render/drawing_json.zig");
```

- [ ] **Step 3: Run all tests to verify nothing broke**

Run: `zig build test 2>&1 | head -30`
Expected: PASS

Run all examples to verify backwards compatibility:
`zig build run-basic 2>&1 | head -20`

- [ ] **Step 4: Commit**

```
refactor: extract layout dispatch to layout.zig, add DrawingIR re-exports

root.zig is now a thin API surface (~200 lines). Layout dispatch
logic lives in layout.zig. All new types (DrawingIR, primitives,
presets) are re-exported for public use.
```
