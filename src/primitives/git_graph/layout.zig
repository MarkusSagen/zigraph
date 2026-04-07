//! Git graph lane-based layout.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const GitGraph = model.GitGraph;

pub const LayoutConfig = struct {
    lane_width: f64 = 40,
    commit_spacing: f64 = 30,
    margin: f64 = 20,
    commit_radius: f64 = 5,
};

pub const GitGraphLayout = struct {
    commit_positions: []Position,
    branch_lanes: []usize,
    total_width: f64,
    total_height: f64,
    allocator: Allocator,

    pub const Position = struct { x: f64, y: f64 };

    pub fn deinit(self: *GitGraphLayout) void {
        self.allocator.free(self.commit_positions);
        self.allocator.free(self.branch_lanes);
    }
};

pub fn layoutGitGraph(gg: *const GitGraph, allocator: Allocator, config: LayoutConfig) !GitGraphLayout {
    const n_commits = gg.commits.items.len;
    const n_branches = gg.branches.items.len;

    var positions = try allocator.alloc(GitGraphLayout.Position, n_commits);
    errdefer allocator.free(positions);

    var lanes = try allocator.alloc(usize, n_branches);
    errdefer allocator.free(lanes);

    // Assign each branch a lane (column) in creation order
    for (0..n_branches) |i| {
        lanes[i] = i;
    }

    // Commits placed top-to-bottom in chronological order
    for (0..n_commits) |i| {
        const commit = gg.commits.items[i];
        const lane = lanes[commit.branch];
        const fi: f64 = @floatFromInt(i);
        const lane_f: f64 = @floatFromInt(lane);
        positions[i] = .{
            .x = config.margin + lane_f * config.lane_width,
            .y = config.margin + fi * config.commit_spacing,
        };
    }

    const n_lanes_f: f64 = @floatFromInt(n_branches);
    const n_commits_f: f64 = @floatFromInt(n_commits);

    return .{
        .commit_positions = positions,
        .branch_lanes = lanes,
        .total_width = config.margin * 2 + n_lanes_f * config.lane_width,
        .total_height = config.margin * 2 + n_commits_f * config.commit_spacing,
        .allocator = allocator,
    };
}

test "git graph layout: commits on lanes" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main_branch = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main_branch, .{});
    const feat = try gg.addBranch("feat", .{});
    _ = try gg.addCommit(feat, .{});

    var result = try layoutGitGraph(&gg, allocator, .{});
    defer result.deinit();

    // Commits on different branches should have different x positions
    try std.testing.expect(result.commit_positions[0].x != result.commit_positions[1].x);
}
