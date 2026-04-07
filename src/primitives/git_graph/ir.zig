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

    const main_branch = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main_branch, .{ .message = "init" });
    _ = try gg.addCommit(main_branch, .{ .message = "feat", .tag = "v1.0" });

    var d = try toDrawing(&gg, allocator, .{});
    defer d.deinit();

    // 1 lane line + 2 commit dots + 2 message labels + 1 tag = 6 min
    try std.testing.expect(d.primitives.items.len >= 6);
}
