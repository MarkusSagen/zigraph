//! Git graph data model — branches, commits, merges.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const CommitId = usize;
pub const BranchId = usize;

pub const BranchOptions = struct {
    from_branch: ?BranchId = null,
};

pub const CommitOptions = struct {
    message: ?[]const u8 = null,
    tag: ?[]const u8 = null,
};

pub const Branch = struct {
    id: BranchId,
    name: []const u8,
    from_branch: ?BranchId,
    head: ?CommitId,
};

pub const Commit = struct {
    id: CommitId,
    branch: BranchId,
    message: ?[]const u8,
    tag: ?[]const u8,
    is_merge: bool,
    merge_from: ?BranchId,
};

pub const GitGraph = struct {
    branches: std.ArrayListUnmanaged(Branch),
    commits: std.ArrayListUnmanaged(Commit),
    allocator: Allocator,
    next_commit_id: CommitId,
    next_branch_id: BranchId,

    pub fn init(allocator: Allocator) GitGraph {
        return .{
            .branches = .{},
            .commits = .{},
            .allocator = allocator,
            .next_commit_id = 0,
            .next_branch_id = 0,
        };
    }

    pub fn deinit(self: *GitGraph) void {
        self.branches.deinit(self.allocator);
        self.commits.deinit(self.allocator);
    }

    pub fn addBranch(self: *GitGraph, name: []const u8, opts: BranchOptions) !BranchId {
        const id = self.next_branch_id;
        self.next_branch_id += 1;
        try self.branches.append(self.allocator, .{
            .id = id,
            .name = name,
            .from_branch = opts.from_branch,
            .head = null,
        });
        return id;
    }

    pub fn addCommit(self: *GitGraph, branch: BranchId, opts: CommitOptions) !CommitId {
        const id = self.next_commit_id;
        self.next_commit_id += 1;
        try self.commits.append(self.allocator, .{
            .id = id,
            .branch = branch,
            .message = opts.message,
            .tag = opts.tag,
            .is_merge = false,
            .merge_from = null,
        });
        self.branches.items[branch].head = id;
        return id;
    }

    pub fn merge(self: *GitGraph, from: BranchId, into: BranchId, opts: CommitOptions) !CommitId {
        const id = self.next_commit_id;
        self.next_commit_id += 1;
        try self.commits.append(self.allocator, .{
            .id = id,
            .branch = into,
            .message = opts.message,
            .tag = opts.tag,
            .is_merge = true,
            .merge_from = from,
        });
        self.branches.items[into].head = id;
        return id;
    }
};

test "git graph: branches and commits" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main_branch = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main_branch, .{ .message = "initial" });
    _ = try gg.addCommit(main_branch, .{ .message = "add feature" });

    const feat = try gg.addBranch("feature", .{ .from_branch = main_branch });
    _ = try gg.addCommit(feat, .{ .message = "wip" });

    try std.testing.expectEqual(@as(usize, 2), gg.branches.items.len);
    try std.testing.expectEqual(@as(usize, 3), gg.commits.items.len);
}

test "git graph: merge creates commit on target branch" {
    const allocator = std.testing.allocator;
    var gg = GitGraph.init(allocator);
    defer gg.deinit();

    const main_branch = try gg.addBranch("main", .{});
    _ = try gg.addCommit(main_branch, .{ .message = "init" });
    const feat = try gg.addBranch("feature", .{ .from_branch = main_branch });
    _ = try gg.addCommit(feat, .{ .message = "work" });

    const merge_id = try gg.merge(feat, main_branch, .{ .message = "merge feature" });

    const commit = gg.commits.items[merge_id];
    try std.testing.expect(commit.is_merge);
    try std.testing.expectEqual(main_branch, commit.branch);
    try std.testing.expectEqual(feat, commit.merge_from.?);
}
