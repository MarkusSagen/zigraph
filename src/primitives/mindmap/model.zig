//! Mindmap data model — radial tree from center.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MindNodeId = usize;

pub const MindShape = enum { rounded_rect, rect, circle, cloud, hexagon };

pub const MindNodeOptions = struct {
    shape: MindShape = .rounded_rect,
};

pub const MindNode = struct {
    id: MindNodeId,
    text: []const u8,
    shape: MindShape,
    parent: ?MindNodeId,
    children: std.ArrayListUnmanaged(MindNodeId),
};

pub const Mindmap = struct {
    nodes: std.ArrayListUnmanaged(MindNode),
    root: ?MindNodeId,
    allocator: Allocator,
    next_id: MindNodeId,

    pub fn init(allocator: Allocator) Mindmap {
        return .{
            .nodes = .{},
            .root = null,
            .allocator = allocator,
            .next_id = 0,
        };
    }

    pub fn deinit(self: *Mindmap) void {
        for (self.nodes.items) |*n| {
            n.children.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
    }

    pub fn addNode(self: *Mindmap, text: []const u8, opts: MindNodeOptions) !MindNodeId {
        const id = self.next_id;
        self.next_id += 1;
        try self.nodes.append(self.allocator, .{
            .id = id,
            .text = text,
            .shape = opts.shape,
            .parent = null,
            .children = .{},
        });
        return id;
    }

    pub fn addChild(self: *Mindmap, parent: MindNodeId, child: MindNodeId) !void {
        self.nodes.items[child].parent = parent;
        try self.nodes.items[parent].children.append(self.allocator, child);
    }

    pub fn setRoot(self: *Mindmap, node: MindNodeId) void {
        self.root = node;
    }
};

test "mindmap: build tree" {
    const allocator = std.testing.allocator;
    var mm = Mindmap.init(allocator);
    defer mm.deinit();

    const root = try mm.addNode("Central Idea", .{});
    mm.setRoot(root);

    const c1 = try mm.addNode("Branch A", .{});
    const c2 = try mm.addNode("Branch B", .{});
    try mm.addChild(root, c1);
    try mm.addChild(root, c2);

    try std.testing.expectEqual(@as(usize, 3), mm.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 2), mm.nodes.items[0].children.items.len);
    try std.testing.expectEqual(root, mm.nodes.items[1].parent.?);
}
