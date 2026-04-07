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
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

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
    return try buf.toOwnedSlice(allocator);
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

// ============================================================================
// Tests
// ============================================================================

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
