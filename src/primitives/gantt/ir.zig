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

    // Milestones as circle markers
    for (gantt.milestones.items) |ms| {
        const day = ms.date.daysSinceEpoch();
        const x: f64 = config.label_width + @as(f64, @floatFromInt(day - gl.min_day)) * gl.day_width;
        const n_tasks_f: f64 = @floatFromInt(gantt.tasks.items.len);
        const y: f64 = config.header_height + n_tasks_f * config.row_height;

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
