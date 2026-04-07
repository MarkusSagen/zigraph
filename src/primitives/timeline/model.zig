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
