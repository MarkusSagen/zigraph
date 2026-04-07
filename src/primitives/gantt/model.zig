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
