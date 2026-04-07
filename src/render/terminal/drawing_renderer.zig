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
    const w: usize = @intFromFloat(@ceil(d.width));
    const h: usize = @intFromFloat(@ceil(d.height));
    if (w == 0 or h == 0) return try allocator.dupe(u8, "");

    var buf = try Buffer2D.init(allocator, w, h);
    defer buf.deinit(allocator);

    for (d.primitives.items) |prim| {
        paintPrimitive(&buf, prim);
    }

    return bufferToString(&buf, allocator);
}

fn bufferToString(buf: *const Buffer2D, allocator: Allocator) ![]u8 {
    var list: std.ArrayListUnmanaged(u8) = .{};
    errdefer list.deinit(allocator);

    for (0..buf.height) |y| {
        const row = buf.getRow(y);
        var end: usize = row.len;
        while (end > 0 and row[end - 1] == ' ') end -= 1;

        for (0..end) |xi| {
            var enc_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(row[xi], &enc_buf) catch 1;
            try list.appendSlice(allocator, enc_buf[0..len]);
        }
        try list.append(allocator, '\n');
    }
    return try list.toOwnedSlice(allocator);
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
        .arc => {}, // Arc approximated as partial circle — deferred to SVG
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
        buf.set(x + col, y, 0x2500); // ─ top
        buf.set(x + col, y + h - 1, 0x2500); // ─ bottom
    }
    var row: usize = 1;
    while (row < h - 1) : (row += 1) {
        buf.set(x, y + row, 0x2502); // │ left
        buf.set(x + w - 1, y + row, 0x2502); // │ right
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
    if (g.border_style != .none and g.width > 0 and g.height > 0) {
        paintRect(buf, .{
            .x = g.x,
            .y = g.y,
            .width = g.width,
            .height = g.height,
            .border_style = g.border_style,
        });
    }
    for (g.children) |child| {
        paintPrimitive(buf, child);
    }
}

fn paintPath(buf: *Buffer2D, pa: drawing.Path) void {
    if (pa.points.len < 2) return;
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

    // Should contain box-drawing characters (UTF-8 encoded)
    try std.testing.expect(std.mem.indexOf(u8, result, "\xe2\x94\x8c") != null); // ┌ = E2 94 8C
    try std.testing.expect(std.mem.indexOf(u8, result, "\xe2\x94\x98") != null); // ┘ = E2 94 98
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

    // Should contain vertical line chars (│ = E2 94 82)
    try std.testing.expect(std.mem.indexOf(u8, result, "\xe2\x94\x82") != null);
}

test "drawing terminal: render circle as dot" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();
    d.setDimensions(10, 3);

    try d.addPrimitive(.{ .circle = .{ .cx = 3, .cy = 1, .radius = 0.5 } });

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "drawing terminal: zero dimensions returns empty string" {
    const allocator = std.testing.allocator;
    var d = Drawing.init(allocator);
    defer d.deinit();

    const result = try renderDrawing(&d, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("", result);
}
