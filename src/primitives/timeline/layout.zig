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
