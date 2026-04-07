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
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    try w.print("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {d} {d}\">\n", .{
        @as(i64, @intFromFloat(d.width)),
        @as(i64, @intFromFloat(d.height)),
    });

    for (d.primitives.items) |prim| {
        try writePrimitive(w, prim);
    }

    try w.writeAll("</svg>\n");
    return buf.toOwnedSlice(allocator);
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

// ============================================================================
// Tests
// ============================================================================

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
