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
