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
