//! Layout dispatch — main entry points for graph layout computation.
//!
//! This module owns the config types and the four public/private layout
//! functions.  `root.zig` re-exports everything from here so the public
//! API is unchanged.

const std = @import("std");

// ── underlying modules (imported directly to avoid circular deps) ────────────

const fp_mod = @import("algorithms/shared/fixed_point.zig");

const graph_mod = @import("core/graph.zig");
const Graph = graph_mod.Graph;

const errors_mod = @import("core/errors.zig");

const ir_mod = @import("core/ir.zig");
const LayoutIR = ir_mod.LayoutIR;

const cycle_breaking = @import("algorithms/sugiyama/cycle_breaking.zig");

const layering = struct {
    const longest_path = @import("algorithms/sugiyama/layering/longest_path.zig");
    const network_simplex = @import("algorithms/sugiyama/layering/network_simplex.zig");
    const virtual = @import("algorithms/sugiyama/layering/virtual.zig");
};

const crossing = struct {
    const reducers = @import("algorithms/sugiyama/crossing/reducers.zig");
    const Reducer = reducers.Reducer;
    const runPipeline = reducers.runPipeline;
    const balanced = reducers.balanced;
};

const positioning = struct {
    const common = @import("algorithms/sugiyama/positioning/common.zig");
    const barycentric = @import("algorithms/sugiyama/positioning/barycentric.zig");
    const brandes_kopf = @import("algorithms/sugiyama/positioning/brandes_kopf.zig");
};

const routing = struct {
    const direct = @import("algorithms/sugiyama/routing/direct.zig");
    const spline = @import("algorithms/sugiyama/routing/spline.zig");
};

const subgraph_layout = @import("algorithms/sugiyama/subgraph.zig");

const fdg = struct {
    const fruchterman_reingold = @import("algorithms/fruchterman_reingold/mod.zig");
};

// ── config types ─────────────────────────────────────────────────────────────

/// Cycle-breaking strategy for handling cyclic graphs in Sugiyama layout.
pub const CycleBreaking = enum {
    /// Reject cyclic graphs with error.CycleDetected (default).
    none,
    /// DFS-based back-edge reversal.
    depth_first,
};

/// Available layering algorithms
pub const Layering = enum {
    longest_path,
    network_simplex,
    network_simplex_fast,
};

/// Available positioning algorithms
pub const Positioning = enum {
    compact,
    barycentric,
    brandes_kopf,
};

/// Available edge routing algorithms
pub const Routing = enum {
    direct,
    spline,
    bus,
};

/// Top-level algorithm selection.
pub const Algorithm = union(enum) {
    sugiyama,
    fruchterman_reingold: fdg.fruchterman_reingold.Config,
    fruchterman_reingold_fast: fdg.fruchterman_reingold.Config,
};

/// Configuration for the layout algorithm.
pub const LayoutConfig = struct {
    algorithm: Algorithm = .sugiyama,
    cycle_breaking: CycleBreaking = .none,
    layering: Layering = .longest_path,
    crossing_reducers: []const crossing.Reducer = &crossing.balanced,
    positioning: Positioning = .compact,
    routing: Routing = .direct,
    node_spacing: usize = 3,
    level_spacing: usize = 2,
    include_dummy_nodes: bool = false,
    skip_validation: bool = false,
    edge_palette: ?[]const u8 = null,
};

/// Layout error type
pub const LayoutError = error{
    EmptyGraph,
    CycleDetected,
} || std.mem.Allocator.Error;

// ── dummy node ID encoding constants ─────────────────────────────────────────

const dummy_id_base: usize = 0x80000000;
const dummy_id_edge_stride: usize = 1000;
const dummy_key_stride: usize = 10000;

// ── public entry points ───────────────────────────────────────────────────────

/// Compute layout for a graph.
pub fn layout(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(usize) {
    return switch (config.algorithm) {
        .sugiyama => layoutSugiyama(g, allocator, config),
        .fruchterman_reingold => |fr_config| layoutFdg(g, allocator, config, fr_config, false),
        .fruchterman_reingold_fast => |fr_config| layoutFdg(g, allocator, config, fr_config, true),
    };
}

/// Compute layout with a user-chosen coordinate type.
pub fn layoutTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(Coord) {
    var usize_result = try layout(g, allocator, config);

    if (Coord == usize) {
        return usize_result;
    }

    defer usize_result.deinit();
    return try usize_result.convertCoord(Coord, allocator);
}

// ── private helpers ───────────────────────────────────────────────────────────

/// Force-directed layout: runs FR, builds LayoutIR from positions.
fn layoutFdg(
    g: *const Graph,
    allocator: std.mem.Allocator,
    _: LayoutConfig,
    fr_config: fdg.fruchterman_reingold.Config,
    fast: bool,
) anyerror!LayoutIR(usize) {
    const n = g.nodeCount();
    if (n == 0) {
        errors_mod.captureError(error.EmptyGraph, @src());
        return error.EmptyGraph;
    }

    var fdg_result = if (fast)
        try fdg.fruchterman_reingold.computeFast(g, allocator, fr_config)
    else
        try fdg.fruchterman_reingold.compute(g, allocator, fr_config);
    defer fdg_result.deinit();

    var result = LayoutIR(usize).init(allocator);
    errdefer result.deinit();

    const max_label_w: usize = blk: {
        var max_w: usize = 3;
        for (0..n) |i| {
            const nd = g.nodeAt(i) orelse continue;
            if (nd.width > max_w) max_w = nd.width;
        }
        break :blk max_w;
    };

    const char_aspect: f64 = 2.0;
    const cell_w: f64 = @floatFromInt(max_label_w + 4);
    const sqrt_n: f64 = @sqrt(@as(f64, @floatFromInt(n)));
    const target_span: f64 = cell_w * (sqrt_n + 1);

    const fdg_w = fp_mod.toFloat(fdg_result.width);
    const fdg_h = fp_mod.toFloat(fdg_result.height);

    const effective_fdg_span = @max(fdg_w, fdg_h / char_aspect);
    const scale: f64 = if (effective_fdg_span > 1.0) target_span / effective_fdg_span else 1.0;
    const scale_x: f64 = scale;
    const scale_y: f64 = scale / char_aspect;

    for (0..n) |node_idx| {
        const node = g.nodeAt(node_idx) orelse continue;
        const pos = fdg_result.positions[node_idx];

        const fx = fp_mod.toFloat(pos.x) * scale_x;
        const fy = fp_mod.toFloat(pos.y) * scale_y;
        const x: usize = @intFromFloat(@max(0.0, @round(fx)));
        const y: usize = @intFromFloat(@max(0.0, @round(fy)));

        try result.addNode(.{
            .id = node.id,
            .label = node.label,
            .lines = node.lines,
            .x = x,
            .y = y,
            .width = node.width,
            .height = node.height,
            .center_x = x + node.width / 2,
            .center_y = y + node.height / 2,
            .level = 0,
            .level_position = node_idx,
            .kind = node.kind,
        });
    }

    // Post-processing: compress large vertical gaps.
    if (result.nodes.items.len > 1) {
        const items = result.nodes.items;
        const node_count = items.len;

        const order = try allocator.alloc(usize, node_count);
        defer allocator.free(order);
        for (order, 0..) |*o, i| o.* = i;
        std.mem.sort(usize, order, items, struct {
            fn cmp(nodes: []ir_mod.LayoutNode(usize), a: usize, b: usize) bool {
                return nodes[a].y < nodes[b].y;
            }
        }.cmp);

        const gap_count = node_count - 1;
        const gaps = try allocator.alloc(usize, gap_count);
        defer allocator.free(gaps);
        for (0..gap_count) |i| {
            gaps[i] = items[order[i + 1]].y -| items[order[i]].y;
        }
        std.mem.sort(usize, gaps, {}, std.sort.asc(usize));

        const median_gap = gaps[gap_count / 2];
        const max_gap = @max(median_gap * 2, 3);

        var shift: usize = 0;
        var prev_y: usize = items[order[0]].y;
        for (1..node_count) |i| {
            const idx = order[i];
            const cur_y = items[idx].y;
            const gap = cur_y -| prev_y;
            if (gap > max_gap) {
                shift += gap - max_gap;
            }
            prev_y = cur_y;
            items[idx].y -|= shift;
        }

        for (items) |*nd| {
            nd.center_x = nd.x + nd.width / 2;
        }
    }

    // Route edges — direct routing for FDG.
    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = g.nodeIndex(edge.from) orelse continue;
        const to_idx = g.nodeIndex(edge.to) orelse continue;

        const from_node = result.nodes.items[from_idx];
        const to_node = result.nodes.items[to_idx];

        var from_x = from_node.center_x;
        const from_y = from_node.y;
        var to_x = to_node.center_x;
        const to_y = to_node.y;

        if (from_y == to_y) {
            if (from_node.x + from_node.width <= to_node.x) {
                from_x = from_node.x + from_node.width;
                to_x = to_node.x;
            } else if (to_node.x + to_node.width <= from_node.x) {
                from_x = from_node.x;
                to_x = to_node.x + to_node.width;
            }
        }

        try result.addEdge(.{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = to_x,
            .to_y = to_y,
            .path = .direct,
            .edge_index = edge_idx,
            .directed = edge.directed,
            .label = edge.label,
        });
    }

    // Compute edge label positions.
    for (result.edges.items) |*edge| {
        const lbl = edge.label orelse continue;
        const label_width = lbl.len + 2;

        const mid_y = if (edge.from_y <= edge.to_y)
            edge.from_y + (edge.to_y - edge.from_y) / 2
        else
            edge.to_y + (edge.from_y - edge.to_y) / 2;

        const mid_x = if (edge.from_x <= edge.to_x)
            edge.from_x + (edge.to_x - edge.from_x) / 2
        else
            edge.to_x + (edge.from_x - edge.to_x) / 2;

        if (edge.from_y == edge.to_y) {
            edge.label_x = if (mid_x >= label_width / 2) mid_x - label_width / 2 else 0;
            edge.label_y = if (mid_y > 0) mid_y - 1 else 0;
        } else {
            edge.label_x = if (mid_x >= label_width / 2) mid_x - label_width / 2 else 0;
            edge.label_y = mid_y;
        }
    }

    var max_x: usize = 1;
    var max_y: usize = 1;
    for (result.nodes.items) |node| {
        const right = node.x + node.width + 2;
        if (right > max_x) max_x = right;
        const bottom = node.y + 2;
        if (bottom > max_y) max_y = bottom;
    }
    for (result.edges.items) |edge| {
        if (edge.label) |lbl| {
            const right = edge.label_x + lbl.len + 2;
            if (right > max_x) max_x = right;
        }
    }
    result.setDimensions(max_x, max_y);

    if (g.hasSubgraphs()) {
        try subgraph_layout.computeBoundingBoxes(g, &result, allocator);

        for (result.subgraphs.items) |sg_info| {
            const right = sg_info.x + sg_info.width;
            const bottom = sg_info.y + sg_info.height;
            if (right > result.width or bottom > result.height) {
                result.setDimensions(@max(result.width, right), @max(result.height, bottom));
            }
        }
    }

    return result;
}

/// Step 0: Validate the graph for Sugiyama layout.
fn validateForSugiyama(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) !void {
    if (config.skip_validation) return;

    var validation_result = try g.validate(allocator);
    defer validation_result.deinit();

    switch (validation_result) {
        .empty => {
            errors_mod.captureError(error.EmptyGraph, @src());
            return error.EmptyGraph;
        },
        .cycle => |cycle_info| {
            if (config.cycle_breaking == .none) {
                var detail_buf: [256]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&detail_buf);
                const w = fbs.writer();
                const max_shown = 5;
                const path = cycle_info.path;
                const total = path.len;
                const show = @min(total, max_shown);
                for (path[0..show], 0..) |node_idx, i| {
                    if (i > 0) w.writeAll(" -> ") catch {};
                    if (g.nodeAt(node_idx)) |node| {
                        w.writeAll(node.label) catch {};
                    } else {
                        w.print("{d}", .{node_idx}) catch {};
                    }
                }
                if (total > max_shown) {
                    w.print(" -> ... (+{d} more)", .{total - max_shown}) catch {};
                }

                var id_buf: [64]usize = undefined;
                const id_count = @min(total, 64);
                for (path[0..id_count], 0..) |node_idx, i| {
                    id_buf[i] = if (g.nodeAt(node_idx)) |node| node.id else node_idx;
                }

                errors_mod.captureErrorFull(error.CycleDetected, @src(), fbs.getWritten(), id_buf[0..id_count]);
                return error.CycleDetected;
            }
        },
        .ok => {},
    }
}

/// Step 3b: Compute effective level spacing based on fan-out and labels.
fn computeEffectiveLevelSpacing(g: *const Graph, config: LayoutConfig) usize {
    const has_edge_labels = blk: {
        for (g.edges.items) |edge| {
            if (edge.label != null) break :blk true;
        }
        break :blk false;
    };
    const label_extra: usize = if (has_edge_labels) 2 else 0;

    var max_fan: usize = 0;
    for (0..g.nodeCount()) |node_idx| {
        const children = g.getChildren(node_idx);
        if (children.len > max_fan) max_fan = children.len;
        const parents = g.getParents(node_idx);
        if (parents.len > max_fan) max_fan = parents.len;
    }
    const needed: usize = if (max_fan > 2)
        @min(2 + std.math.sqrt(max_fan), 8)
    else
        2;
    return @max(config.level_spacing, needed) + label_extra;
}

/// Step 6b: Fix up reversed (back) edges in the IR.
fn fixupReversedEdges(result: *LayoutIR(usize), reversed_edges: ?[]const bool) void {
    const re = reversed_edges orelse return;

    for (result.edges.items) |*result_edge| {
        if (result_edge.edge_index < re.len and re[result_edge.edge_index]) {
            result_edge.reversed = true;
            const tmp_id = result_edge.from_id;
            result_edge.from_id = result_edge.to_id;
            result_edge.to_id = tmp_id;
        }
    }

    for (0..re.len) |edge_idx| {
        if (!re[edge_idx]) continue;

        var first_seg: ?*ir_mod.LayoutEdge(usize) = null;
        var last_seg: ?*ir_mod.LayoutEdge(usize) = null;
        for (result.edges.items) |*seg| {
            if (seg.edge_index != edge_idx) continue;
            if (first_seg == null or seg.from_y < first_seg.?.from_y) {
                first_seg = seg;
            }
            if (last_seg == null or seg.from_y > last_seg.?.from_y) {
                last_seg = seg;
            }
        }

        if (first_seg != null and last_seg != null and first_seg != last_seg) {
            const was_directed = last_seg.?.directed;
            last_seg.?.directed = false;
            first_seg.?.directed = was_directed;
        }
    }
}

/// Find a safe horizontal_y for a split edge segment, avoiding node collisions.
fn findSafeSplitHorizontalY(
    initial_h_y: usize,
    min_h_y: usize,
    max_h_y: usize,
    x_from: usize,
    x_to: usize,
    nodes: []const ir_mod.LayoutNode(usize),
    from_id: usize,
    to_id: usize,
) usize {
    const x_lo = @min(x_from, x_to);
    const x_hi = @max(x_from, x_to);

    if (!splitHorizontalCollides(initial_h_y, x_lo, x_hi, nodes, from_id, to_id)) {
        return initial_h_y;
    }
    var offset: usize = 1;
    const range = if (max_h_y >= min_h_y) max_h_y - min_h_y + 1 else 1;
    while (offset <= range) : (offset += 1) {
        if (initial_h_y >= min_h_y + offset) {
            const candidate = initial_h_y - offset;
            if (candidate >= min_h_y and !splitHorizontalCollides(candidate, x_lo, x_hi, nodes, from_id, to_id)) {
                return candidate;
            }
        }
        {
            const candidate = initial_h_y + offset;
            if (candidate <= max_h_y and !splitHorizontalCollides(candidate, x_lo, x_hi, nodes, from_id, to_id)) {
                return candidate;
            }
        }
    }
    return initial_h_y;
}

/// Check if a horizontal segment at h_y collides with any real node.
fn splitHorizontalCollides(
    h_y: usize,
    x_lo: usize,
    x_hi: usize,
    nodes: []const ir_mod.LayoutNode(usize),
    from_id: usize,
    to_id: usize,
) bool {
    for (nodes) |n| {
        if (n.id == from_id or n.id == to_id) continue;
        if (n.kind == .dummy) continue;
        const node_y_min = if (n.y > 0) n.y - 1 else 0;
        const node_y_max = n.y + n.height;
        if (h_y < node_y_min or h_y > node_y_max) continue;
        const node_x_max = n.x + n.width;
        if (x_hi < n.x or x_lo > node_x_max) continue;
        return true;
    }
    return false;
}

/// Stagger horizontal_y for corner-path edges to reduce crossings.
fn staggerCornerEdges(result: *LayoutIR(usize)) void {
    const edges = result.edges.items;
    const n = edges.len;
    if (n == 0) return;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (edges[i].path != .corner) continue;
        const group_from_y = edges[i].from_y;

        const my_dist = if (edges[i].to_x >= edges[i].from_x)
            edges[i].to_x - edges[i].from_x
        else
            edges[i].from_x - edges[i].to_x;

        var slot: usize = 0;
        for (edges[0..n]) |*prev| {
            if (@intFromPtr(prev) == @intFromPtr(&edges[i])) continue;
            if (prev.path != .corner) continue;
            if (prev.from_y != group_from_y) continue;
            const prev_dist = if (prev.to_x >= prev.from_x)
                prev.to_x - prev.from_x
            else
                prev.from_x - prev.to_x;
            if (prev_dist > my_dist) {
                slot += 1;
            } else if (prev_dist == my_dist) {
                if (prev.to_x < edges[i].to_x) {
                    slot += 1;
                }
            }
        }

        const available = if (edges[i].to_y > edges[i].from_y + 1)
            edges[i].to_y - edges[i].from_y - 1
        else
            1;
        const initial_h_y = edges[i].from_y + (slot % available);
        const min_h_y = edges[i].from_y + 1;
        const max_h_y = if (edges[i].to_y > 1) edges[i].to_y - 1 else min_h_y;
        edges[i].path.corner.horizontal_y = findSafeSplitHorizontalY(
            initial_h_y,
            if (min_h_y <= max_h_y) min_h_y else initial_h_y,
            if (max_h_y >= min_h_y) max_h_y else initial_h_y,
            edges[i].from_x,
            edges[i].to_x,
            result.nodes.items,
            edges[i].from_id,
            edges[i].to_id,
        );
    }
}

/// Step 8: Propagate edge labels from the input graph to the IR edges.
fn propagateEdgeLabels(result: *LayoutIR(usize), g: *const Graph, allocator: std.mem.Allocator) !void {
    var label_assigned = try allocator.alloc(bool, g.edges.items.len);
    defer allocator.free(label_assigned);
    @memset(label_assigned, false);

    for (result.edges.items) |*edge| {
        const orig_idx = edge.edge_index;
        if (orig_idx >= g.edges.items.len) continue;

        const orig_label = g.edges.items[orig_idx].label orelse continue;
        if (label_assigned[orig_idx]) continue;
        label_assigned[orig_idx] = true;

        edge.label = orig_label;

        var label_y: usize = undefined;
        var edge_x_at_label: usize = undefined;

        switch (edge.path) {
            .direct => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
            .corner => |c| {
                if (c.horizontal_y + 1 < edge.to_y) {
                    label_y = c.horizontal_y + 1;
                } else if (c.horizontal_y > edge.from_y + 1) {
                    label_y = c.horizontal_y - 1;
                } else {
                    label_y = edge.from_y + 1;
                }
                edge_x_at_label = edge.to_x;
            },
            .side_channel => |sc| {
                label_y = if (sc.start_y + 1 < sc.end_y)
                    sc.start_y + 1
                else if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = sc.channel_x;
            },
            .multi_segment => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
            .spline => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
            .bus => {},
        }

        const label_width = orig_label.len + 2;
        const label_x = if (edge_x_at_label >= label_width / 2)
            edge_x_at_label - label_width / 2
        else
            0;

        edge.label_x = label_x;
        edge.label_y = label_y;
    }
}

/// Step 9: Widen layout if edge labels extend beyond current width.
fn widenForLabels(result: *LayoutIR(usize), total_width: usize, total_height: usize) void {
    var needed_width = total_width;
    for (result.edges.items) |edge| {
        if (edge.label) |lbl| {
            const right = edge.label_x + lbl.len + 2;
            if (right > needed_width) needed_width = right;
        }
    }
    result.setDimensions(needed_width, total_height);
}

/// Compute layout using the Sugiyama hierarchical algorithm.
fn layoutSugiyama(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(usize) {
    // Step 0: Validate graph (unless skipped)
    try validateForSugiyama(g, allocator, config);

    // Step 0b: Cycle breaking
    const reversed_edges: ?[]bool = switch (config.cycle_breaking) {
        .none => null,
        .depth_first => try cycle_breaking.detectBackEdges(g, allocator),
    };
    defer if (reversed_edges) |re| allocator.free(re);

    // Step 1: Layer assignment
    var layer_assignment = switch (config.layering) {
        .longest_path => try layering.longest_path.computeWithReversed(g, allocator, reversed_edges),
        .network_simplex => try layering.network_simplex.computeWithReversed(g, allocator, reversed_edges),
        .network_simplex_fast => try layering.network_simplex.computeFastWithReversed(g, allocator, reversed_edges),
    };
    defer layer_assignment.deinit();

    // Step 1a: Apply pin.y constraints and enforce subgraph contiguity
    {
        // Phase 1: Apply pin.y hints
        for (0..g.nodeCount()) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            const pin = node.pin orelse continue;
            if (pin.y) |pinned_level| {
                layer_assignment.levels[node_idx] = pinned_level;
                layer_assignment.max_level = @max(layer_assignment.max_level, pinned_level);
            }
        }

        // Phase 1b: Enforce contiguous level spans for subgraph members.
        if (g.hasSubgraphs()) {
            try subgraph_layout.enforceContiguousLevels(g, &layer_assignment, allocator);
        }

        // Phase 2: Topological repair
        var changed = true;
        var safety: usize = 0;
        const max_iters = g.nodeCount() + 1;
        while (changed and safety < max_iters) : (safety += 1) {
            changed = false;
            for (g.edges.items, 0..) |edge, edge_idx| {
                const is_reversed = if (reversed_edges) |re| re[edge_idx] else false;
                const from_id = if (is_reversed) edge.to else edge.from;
                const to_id = if (is_reversed) edge.from else edge.to;

                const from_idx = g.nodeIndex(from_id) orelse continue;
                const to_idx = g.nodeIndex(to_id) orelse continue;
                if (from_idx == to_idx) continue;

                const to_node = g.nodeAt(to_idx) orelse continue;
                if (to_node.pin) |to_pin| {
                    if (to_pin.y != null) continue;
                }

                if (layer_assignment.levels[to_idx] <= layer_assignment.levels[from_idx]) {
                    layer_assignment.levels[to_idx] = layer_assignment.levels[from_idx] + 1;
                    layer_assignment.max_level = @max(layer_assignment.max_level, layer_assignment.levels[to_idx]);
                    changed = true;
                }
            }
        }

        // Phase 3: Level compaction
        {
            const node_count = g.nodeCount();

            const unique_buf = try allocator.alloc(usize, node_count);
            defer allocator.free(unique_buf);
            var unique_count: usize = 0;

            for (0..node_count) |ni| {
                const lev = layer_assignment.levels[ni];
                var found = false;
                for (0..unique_count) |ui| {
                    if (unique_buf[ui] == lev) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    unique_buf[unique_count] = lev;
                    unique_count += 1;
                }
            }

            const unique_levels = unique_buf[0..unique_count];
            for (1..unique_count) |i| {
                const key = unique_levels[i];
                var j: usize = i;
                while (j > 0 and unique_levels[j - 1] > key) {
                    unique_levels[j] = unique_levels[j - 1];
                    j -= 1;
                }
                unique_levels[j] = key;
            }

            for (0..node_count) |ni| {
                const old_level = layer_assignment.levels[ni];
                for (unique_levels, 0..) |ul, rank| {
                    if (ul == old_level) {
                        layer_assignment.levels[ni] = rank;
                        break;
                    }
                }
            }

            layer_assignment.max_level = if (unique_count > 0) unique_count - 1 else 0;
        }
    }

    // Step 1b: Promote subgraph root/isolated nodes closer to siblings.
    if (g.hasSubgraphs()) {
        try subgraph_layout.promoteSubgraphRoots(g, &layer_assignment, allocator);

        var new_max: usize = 0;
        for (0..g.nodeCount()) |ni| {
            new_max = @max(new_max, layer_assignment.levels[ni]);
        }
        layer_assignment.max_level = new_max;
    }

    // Step 2: Build virtual levels (includes dummy nodes for skip-level edges)
    var virtual_levels = try layering.virtual.buildVirtualLevelsWithReversed(
        g,
        layer_assignment.levels,
        layer_assignment.max_level,
        allocator,
        reversed_edges,
    );
    defer virtual_levels.deinit();

    // Step 3: Crossing reduction
    if (g.hasSubgraphs() and config.crossing_reducers.len > 0) {
        var total_passes: usize = 0;
        for (config.crossing_reducers) |r| total_passes += r.passes;
        if (total_passes > 0) {
            try subgraph_layout.blockBasedCrossingReduction(g, &virtual_levels, total_passes, allocator);
        }
    } else {
        try crossing.runPipeline(config.crossing_reducers, &virtual_levels, g, allocator);
    }

    // Step 3b: Compute adaptive level spacing
    const effective_level_spacing = computeEffectiveLevelSpacing(g, config);

    // Step 4: Position nodes
    var virtual_positions = switch (config.positioning) {
        .compact => try layering.virtual.computeVirtualPositions(
            g,
            &virtual_levels,
            config.node_spacing,
            effective_level_spacing,
            allocator,
        ),
        .barycentric, .brandes_kopf => blk: {
            var real_node_levels = try layering.virtual.extractRealNodeLevels(&virtual_levels, allocator);
            defer {
                for (real_node_levels.items) |*level| level.deinit(allocator);
                real_node_levels.deinit(allocator);
            }

            const levels_slice = real_node_levels.items;
            const pos_config = positioning.common.Config{
                .node_spacing = config.node_spacing,
                .level_spacing = effective_level_spacing,
            };

            var pos_assignment = switch (config.positioning) {
                .brandes_kopf => try positioning.brandes_kopf.compute(g, levels_slice, pos_config, allocator),
                .barycentric => try positioning.barycentric.compute(g, levels_slice, pos_config, allocator),
                .compact => unreachable,
            };
            defer pos_assignment.deinit();

            break :blk try layering.virtual.computeVirtualPositionsWithHints(
                g,
                &virtual_levels,
                config.node_spacing,
                effective_level_spacing,
                pos_assignment.x,
                allocator,
            );
        },
    };
    defer virtual_positions.deinit();

    // Step 4a: Apply subgraph horizontal padding
    if (g.hasSubgraphs()) {
        try subgraph_layout.applySubgraphPadding(g, &virtual_levels, &virtual_positions, allocator);
    }

    // Step 4a-y: Compute per-level y-offsets for subgraph top/bottom borders
    const level_y_offsets: ?[]usize = if (g.hasSubgraphs())
        try subgraph_layout.computeLevelYOffsets(g, &virtual_levels, allocator)
    else
        null;
    defer if (level_y_offsets) |offsets| allocator.free(offsets);

    // Build cumulative y-offsets
    var cumulative_y: []usize = &.{};
    defer if (cumulative_y.len > 0) allocator.free(cumulative_y);
    if (level_y_offsets) |offsets| {
        cumulative_y = try allocator.alloc(usize, offsets.len);
        var accum: usize = 0;
        for (offsets, 0..) |off, i| {
            accum += off;
            cumulative_y[i] = accum;
        }
    }

    // Step 4b: Extract real node positions from virtual positions
    var real_positions = try layering.virtual.extractRealNodePositions(
        g,
        &virtual_levels,
        &virtual_positions,
        effective_level_spacing,
        allocator,
    );
    defer real_positions.deinit();

    // Step 4c: Extract dummy positions from virtual positions
    var dummy_positions = try layering.virtual.extractDummyPositions(
        &virtual_levels,
        &virtual_positions,
        g.edges.items.len,
        effective_level_spacing,
        real_positions.level_y,
        allocator,
    );
    defer dummy_positions.deinit();

    // Step 4d: Apply vertical subgraph padding (y-offsets for border rows)
    if (cumulative_y.len > 0) {
        for (0..g.nodeCount()) |node_idx| {
            const lvl = real_positions.level[node_idx];
            if (lvl < cumulative_y.len) {
                real_positions.y[node_idx] += cumulative_y[lvl];
                real_positions.center_y[node_idx] += cumulative_y[lvl];
            }
        }
        for (real_positions.level_y, 0..) |*ly, lvl| {
            if (lvl < cumulative_y.len) {
                ly.* += cumulative_y[lvl];
            }
        }
        for (dummy_positions.waypoints.items) |*edge_wps| {
            for (edge_wps.items) |*wp| {
                var best_level: usize = 0;
                var best_dist: usize = std.math.maxInt(usize);
                const pre_shift_level_y = real_positions.level_y;
                for (pre_shift_level_y, 0..) |ly, li| {
                    const orig_ly = if (li < cumulative_y.len) ly - cumulative_y[li] else ly;
                    const dist = if (wp.level >= orig_ly) wp.level - orig_ly else orig_ly - wp.level;
                    if (dist < best_dist) {
                        best_dist = dist;
                        best_level = li;
                    }
                }
                if (best_level < cumulative_y.len) {
                    wp.level += cumulative_y[best_level];
                }
            }
        }
        const total_extra_y = cumulative_y[cumulative_y.len - 1];
        real_positions.total_height += total_extra_y;
        virtual_positions.total_height += total_extra_y;
    }

    // Step 4e: Refine + compact subgraphs, then fix overlaps
    if (g.subgraphCount() >= 2) {
        const node_widths = try allocator.alloc(usize, g.nodeCount());
        defer allocator.free(node_widths);
        for (0..g.nodeCount()) |ni| {
            node_widths[ni] = if (g.nodeAt(ni)) |n| n.width else 1;
        }

        try subgraph_layout.refineAndCompact(
            g,
            real_positions.x,
            real_positions.level,
            node_widths,
            g.nodeCount(),
            allocator,
        );

        const extra_w = try subgraph_layout.fixSubgraphOverlaps(
            g,
            real_positions.x,
            real_positions.level,
            node_widths,
            g.nodeCount(),
            allocator,
        );
        real_positions.total_width += extra_w;
        for (0..g.nodeCount()) |ni| {
            real_positions.center_x[ni] = real_positions.x[ni] + node_widths[ni] / 2;
        }
    }

    // Step 5: Build LayoutIR
    var result = LayoutIR(usize).init(allocator);
    errdefer result.deinit();

    // Add real nodes
    for (0..g.nodeCount()) |node_idx| {
        const node = g.nodeAt(node_idx) orelse continue;
        try result.addNode(.{
            .id = node.id,
            .label = node.label,
            .lines = node.lines,
            .x = real_positions.x[node_idx],
            .y = real_positions.y[node_idx],
            .width = node.width,
            .height = real_positions.height[node_idx],
            .center_x = real_positions.center_x[node_idx],
            .center_y = real_positions.center_y[node_idx],
            .level = real_positions.level[node_idx],
            .level_position = real_positions.level_position[node_idx],
            .kind = node.kind,
        });
        try result.addNodeToLevel(real_positions.level[node_idx], result.nodes.items.len - 1);
    }

    // Build dummy node mapping for edge splitting
    var dummy_id_map = std.AutoHashMap(usize, usize).init(allocator);
    defer dummy_id_map.deinit();

    for (virtual_levels.levels.items, 0..) |level, level_idx| {
        for (level.items, 0..) |vnode, pos_in_level| {
            if (vnode.dummyEdge()) |edge_idx| {
                const x = virtual_positions.x.items[level_idx].items[pos_in_level];
                const y = if (level_idx < real_positions.level_y.len)
                    real_positions.level_y[level_idx]
                else
                    level_idx * (1 + effective_level_spacing);

                const dummy_id = dummy_id_base + edge_idx * dummy_id_edge_stride + level_idx;

                try result.addNode(.{
                    .id = dummy_id,
                    .label = "O",
                    .x = x,
                    .y = y,
                    .width = 1,
                    .height = 1,
                    .center_x = x,
                    .center_y = y,
                    .level = level_idx,
                    .level_position = pos_in_level,
                    .kind = .dummy,
                    .edge_index = edge_idx,
                });

                const key = edge_idx * dummy_key_stride + level_idx;
                try dummy_id_map.put(key, dummy_id);
            }
        }
    }

    // Step 6: Edge routing (with dummy node support)
    var routed_edges = switch (config.routing) {
        .direct => try routing.direct.routeWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            reversed_edges,
        ),
        .spline => try routing.spline.routeWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            .{},
            reversed_edges,
        ),
        .bus => try routing.direct.routeBusWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            reversed_edges,
        ),
    };
    defer routed_edges.deinit(allocator);

    // Always split edges through dummy nodes
    if (dummy_id_map.count() > 0) {
        for (routed_edges.items, 0..) |*edge, edge_idx| {
            const from_node = result.nodes.items[result.id_to_index.get(edge.from_id).?];
            const to_node = result.nodes.items[result.id_to_index.get(edge.to_id).?];

            const level_span = if (to_node.level > from_node.level)
                to_node.level - from_node.level
            else
                0;

            if (level_span > 1) {
                edge.path.deinit();

                var prev_id = edge.from_id;
                var prev_x = edge.from_x;
                var prev_y = edge.from_y;

                for ((from_node.level + 1)..(to_node.level)) |intermediate_level| {
                    const key = edge_idx * dummy_key_stride + intermediate_level;
                    if (dummy_id_map.get(key)) |dummy_id| {
                        const dummy_node = result.nodes.items[result.id_to_index.get(dummy_id).?];

                        const edge_path: ir_mod.EdgePath(usize) = if (prev_x == dummy_node.center_x)
                            .direct
                        else blk: {
                            const min_h_y = prev_y + 1;
                            const max_h_y = if (dummy_node.y > 1) dummy_node.y - 1 else min_h_y;
                            const h_y = findSafeSplitHorizontalY(
                                min_h_y,
                                min_h_y,
                                max_h_y,
                                prev_x,
                                dummy_node.center_x,
                                result.nodes.items,
                                prev_id,
                                dummy_id,
                            );
                            break :blk .{ .corner = .{ .horizontal_y = h_y } };
                        };

                        try result.addEdge(.{
                            .from_id = prev_id,
                            .to_id = dummy_id,
                            .from_x = prev_x,
                            .from_y = prev_y,
                            .to_x = dummy_node.center_x,
                            .to_y = dummy_node.y,
                            .path = edge_path,
                            .edge_index = edge_idx,
                            .directed = false,
                        });

                        prev_id = dummy_id;
                        prev_x = dummy_node.center_x;
                        prev_y = dummy_node.y + dummy_node.height;
                    }
                }

                const final_path: ir_mod.EdgePath(usize) = if (prev_x == edge.to_x)
                    .direct
                else blk: {
                    const min_h_y = prev_y + 1;
                    const max_h_y = if (edge.to_y > 1) edge.to_y - 1 else min_h_y;
                    const h_y = findSafeSplitHorizontalY(
                        min_h_y,
                        min_h_y,
                        max_h_y,
                        prev_x,
                        edge.to_x,
                        result.nodes.items,
                        prev_id,
                        edge.to_id,
                    );
                    break :blk .{ .corner = .{ .horizontal_y = h_y } };
                };

                try result.addEdge(.{
                    .from_id = prev_id,
                    .to_id = edge.to_id,
                    .from_x = prev_x,
                    .from_y = prev_y,
                    .to_x = edge.to_x,
                    .to_y = edge.to_y,
                    .path = final_path,
                    .edge_index = edge_idx,
                    .directed = edge.directed,
                });
            } else {
                try result.addEdge(edge.*);
            }
        }
    } else {
        for (routed_edges.items) |edge| {
            try result.addEdge(edge);
        }
    }

    // Step 6b: Fix up reversed (back) edges
    fixupReversedEdges(&result, reversed_edges);

    // Step 7: Stagger horizontal_y for corner edges
    staggerCornerEdges(&result);

    // Step 8: Propagate edge labels and compute label positions
    try propagateEdgeLabels(&result, g, allocator);

    // Step 9: Widen layout if labels extend beyond current width
    widenForLabels(&result, real_positions.total_width, real_positions.total_height);

    // Step 10: Compute subgraph bounding boxes
    if (g.hasSubgraphs()) {
        try subgraph_layout.computeBoundingBoxes(g, &result, allocator);

        for (result.subgraphs.items) |sg_info| {
            const right = sg_info.x + sg_info.width;
            const bottom = sg_info.y + sg_info.height;
            if (right > result.width or bottom > result.height) {
                result.setDimensions(@max(result.width, right), @max(result.height, bottom));
            }
        }
    }

    return result;
}
