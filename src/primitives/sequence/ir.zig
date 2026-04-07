//! SequenceIR → DrawingIR conversion.

const std = @import("std");
const Allocator = std.mem.Allocator;
const model = @import("model.zig");
const Sequence = model.Sequence;
const layout_mod = @import("layout.zig");
const SequenceLayout = layout_mod.SequenceLayout;
const layoutSequence = layout_mod.layoutSequence;
const LayoutConfig = layout_mod.LayoutConfig;
const drawing = @import("../../drawing/ir.zig");
const Drawing = drawing.Drawing;

/// Lay out a sequence diagram and convert to DrawingIR.
pub fn toDrawing(seq: *const Sequence, allocator: Allocator, config: LayoutConfig) !Drawing {
    var sl = try layoutSequence(seq, allocator, config);
    defer sl.deinit();

    var d = Drawing.init(allocator);
    errdefer d.deinit();
    d.setDimensions(sl.total_width, sl.total_height);

    // Actor boxes at top
    for (seq.actors.items, 0..) |actor, i| {
        const cx = sl.actor_positions[i];
        const bw = config.actor_box_width;
        const bh = config.actor_box_height;

        try d.addPrimitive(.{ .rect = .{
            .x = cx - bw / 2,
            .y = config.margin,
            .width = bw,
            .height = bh,
        } });
        try d.addPrimitive(.{ .text = .{
            .x = cx,
            .y = config.margin + bh / 2,
            .content = actor.name,
            .alignment = .center,
        } });

        // Lifeline (dashed vertical line from bottom of box to diagram bottom)
        try d.addPrimitive(.{ .line = .{
            .x1 = cx,
            .y1 = config.margin + bh,
            .x2 = cx,
            .y2 = sl.total_height - config.margin,
            .style = .dashed,
        } });
    }

    // Messages as horizontal arrows
    for (seq.messages.items, 0..) |msg, i| {
        const from_x = sl.actor_positions[msg.from];
        const to_x = sl.actor_positions[msg.to];
        const y = sl.message_ys[i];

        const marker: drawing.MarkerType = switch (msg.style) {
            .sync => .arrow,
            .async_msg => .hollow_arrow,
            .@"return" => .arrow,
            .create, .destroy => .arrow,
        };
        const line_style: drawing.BorderStyle = if (msg.style == .@"return") .dashed else .solid;

        try d.addPrimitive(.{ .line = .{
            .x1 = from_x,
            .y1 = y,
            .x2 = to_x,
            .y2 = y,
            .end_marker = marker,
            .style = line_style,
        } });

        // Message label above the arrow
        const label_x = (from_x + to_x) / 2;
        try d.addPrimitive(.{ .text = .{
            .x = label_x,
            .y = y - 5,
            .content = msg.text,
            .alignment = .center,
            .font_size = 12,
        } });
    }

    // Fragments as bordered rectangles
    for (seq.fragments.items) |frag| {
        if (frag.start_message >= sl.message_ys.len or frag.end_message >= sl.message_ys.len) continue;
        const top_y = sl.message_ys[frag.start_message] - 15;
        const bot_y = sl.message_ys[frag.end_message] + 15;

        try d.addPrimitive(.{ .rect = .{
            .x = config.margin,
            .y = top_y,
            .width = sl.total_width - 2 * config.margin,
            .height = bot_y - top_y,
            .border_style = .dashed,
        } });
        try d.addPrimitive(.{ .text = .{
            .x = config.margin + 5,
            .y = top_y + 12,
            .content = frag.label,
            .alignment = .left,
            .style = .{ .bold = true },
            .font_size = 11,
        } });
    }

    return d;
}

test "sequence ir: basic sequence to drawing" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    const a = try seq.addActor("Client", .{});
    const b = try seq.addActor("Server", .{});
    _ = try seq.addMessage(a, b, "GET /api", .{});
    _ = try seq.addMessage(b, a, "200 OK", .{ .style = .@"return" });

    var d = try toDrawing(&seq, allocator, .{});
    defer d.deinit();

    // Should have: 2 actor boxes + 2 actor labels + 2 lifelines + 2 message lines + 2 message labels = 10
    try std.testing.expect(d.primitives.items.len >= 10);
    try std.testing.expect(d.width > 0);
    try std.testing.expect(d.height > 0);
}

test "sequence ir: empty sequence" {
    const allocator = std.testing.allocator;
    var seq = Sequence.init(allocator);
    defer seq.deinit();

    var d = try toDrawing(&seq, allocator, .{});
    defer d.deinit();

    try std.testing.expectEqual(@as(usize, 0), d.primitives.items.len);
}
