//! Sequence diagram data model.
//!
//! Actors, messages, and fragments for interaction diagrams.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ActorId = usize;
pub const MessageId = usize;

pub const ActorType = enum { participant, actor, database, queue, boundary };

pub const MessageStyle = enum { sync, async_msg, @"return", create, destroy };

pub const FragmentKind = enum { loop, alt, opt, par, @"break", critical, ref };

pub const ActorOptions = struct {
    actor_type: ActorType = .participant,
};

pub const MessageOptions = struct {
    style: MessageStyle = .sync,
    activate: bool = false,
    deactivate: bool = false,
};

pub const Actor = struct {
    id: ActorId,
    name: []const u8,
    actor_type: ActorType,
};

pub const Message = struct {
    id: MessageId,
    from: ActorId,
    to: ActorId,
    text: []const u8,
    style: MessageStyle,
    activate: bool,
    deactivate: bool,
};

pub const Fragment = struct {
    kind: FragmentKind,
    label: []const u8,
    start_message: MessageId,
    end_message: MessageId,
};

pub const Sequence = struct {
    actors: std.ArrayListUnmanaged(Actor),
    messages: std.ArrayListUnmanaged(Message),
    fragments: std.ArrayListUnmanaged(Fragment),
    allocator: Allocator,
    next_actor_id: ActorId,
    next_message_id: MessageId,

    pub fn init(allocator: Allocator) Sequence {
        return .{
            .actors = .{},
            .messages = .{},
            .fragments = .{},
            .allocator = allocator,
            .next_actor_id = 0,
            .next_message_id = 0,
        };
    }

    pub fn deinit(self: *Sequence) void {
        self.actors.deinit(self.allocator);
        self.messages.deinit(self.allocator);
        self.fragments.deinit(self.allocator);
    }

    pub fn addActor(self: *Sequence, name: []const u8, opts: ActorOptions) !ActorId {
        const id = self.next_actor_id;
        self.next_actor_id += 1;
        try self.actors.append(self.allocator, .{
            .id = id,
            .name = name,
            .actor_type = opts.actor_type,
        });
        return id;
    }

    pub fn addMessage(self: *Sequence, from: ActorId, to: ActorId, text: []const u8, opts: MessageOptions) !MessageId {
        const id = self.next_message_id;
        self.next_message_id += 1;
        try self.messages.append(self.allocator, .{
            .id = id,
            .from = from,
            .to = to,
            .text = text,
            .style = opts.style,
            .activate = opts.activate,
            .deactivate = opts.deactivate,
        });
        return id;
    }

    pub fn addFragment(self: *Sequence, kind: FragmentKind, start_msg: MessageId, end_msg: MessageId, label: []const u8) !void {
        try self.fragments.append(self.allocator, .{
            .kind = kind,
            .label = label,
            .start_message = start_msg,
            .end_message = end_msg,
        });
    }
};

test "sequence: create actors" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{ .actor_type = .database });

    try std.testing.expectEqual(@as(ActorId, 0), a);
    try std.testing.expectEqual(@as(ActorId, 1), b);
    try std.testing.expectEqual(@as(usize, 2), seq.actors.items.len);
    try std.testing.expectEqualStrings("Server", seq.actors.items[1].name);
    try std.testing.expectEqual(ActorType.database, seq.actors.items[1].actor_type);
}

test "sequence: add messages" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{});

    const m1 = try seq.addMessage(a, b, "request", .{});
    const m2 = try seq.addMessage(b, a, "response", .{ .style = .@"return" });

    try std.testing.expectEqual(@as(MessageId, 0), m1);
    try std.testing.expectEqual(@as(MessageId, 1), m2);
    try std.testing.expectEqual(@as(usize, 2), seq.messages.items.len);
}

test "sequence: add fragment" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("A", .{});
    const b = try seq.addActor("B", .{});

    const m1 = try seq.addMessage(a, b, "ping", .{});
    const m2 = try seq.addMessage(b, a, "pong", .{});

    try seq.addFragment(.loop, m1, m2, "retry 3x");

    try std.testing.expectEqual(@as(usize, 1), seq.fragments.items.len);
    try std.testing.expectEqual(FragmentKind.loop, seq.fragments.items[0].kind);
}
