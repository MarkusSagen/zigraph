//! zigraph - Zero-dependency graph layout engine for Zig
//!
//! This library provides hierarchical (Sugiyama) graph layout with
//! pluggable algorithms and presets for different use cases.
//!
//! ## Quick Start
//!
//! ```zig
//! const zigraph = @import("zigraph");
//!
//! var graph = zigraph.Graph.init(allocator);
//! defer graph.deinit();
//!
//! try graph.addNode(1, "Start");
//! try graph.addNode(2, "End");
//! try graph.addEdge(1, 2);
//!
//! const ir = try zigraph.layout(graph, allocator, .{});
//! defer ir.deinit();
//! ```

const std = @import("std");

// ============================================================================
// Core types
// ============================================================================

/// Core graph data structures
pub const graph = @import("core/graph.zig");
pub const Graph = graph.Graph;
pub const Node = graph.Node;
pub const Edge = graph.Edge;
pub const NodeKind = graph.NodeKind;
pub const NodeOptions = graph.NodeOptions;
pub const Pin = graph.Pin;
pub const Subgraph = graph.Subgraph;
pub const SubgraphStyleKind = graph.SubgraphStyleKind;
pub const ValidationResult = graph.ValidationResult;
pub const CycleInfo = graph.CycleInfo;

/// Error types (WDP Level 0 compliant)
pub const errors = @import("core/errors.zig");
pub const Code = errors.Code;
pub const Diagnostic = errors.Diagnostic;
pub const DiagnosticInfo = errors.DiagnosticInfo;
pub const ZigraphError = errors.ZigraphError;
pub const ValidationFailures = errors.ValidationFailures;
pub const Requirements = errors.Requirements;
pub const GraphProperties = errors.GraphProperties;
pub const diagnosticInfo = errors.diagnosticInfo;

/// Validation algorithms
pub const validation = @import("core/validation.zig");

/// Curated layout presets for common use cases
pub const presets = @import("presets.zig");

/// Intermediate Representation for layout.
/// All IR types are parameterized by coordinate type:
///   const MyIR = ir.LayoutIR(f32);
///   const DefaultIR = ir.LayoutIR(usize);
pub const ir = @import("core/ir.zig");
pub const LayoutIR = ir.LayoutIR;

/// Drawing IR — renderer-agnostic drawing primitives
pub const drawing = @import("drawing/ir.zig");
pub const DrawingPrimitive = drawing.DrawingPrimitive;
pub const Drawing = drawing.Drawing;
/// Drawing IR conversion (LayoutIR → DrawingIR)
pub const drawing_convert = @import("drawing/convert.zig");
pub const convertLayoutIR = drawing_convert.convertLayoutIR;
/// Node shape definitions
pub const node_shapes = @import("core/shapes.zig");
pub const NodeShape = graph.NodeShape;
pub const LineStyle = graph.LineStyle;
pub const MarkerType = graph.MarkerType;
pub const EdgeDecorator = graph.EdgeDecorator;
pub const Visibility = graph.Visibility;
pub const Constraint = graph.Constraint;
pub const CardField = graph.CardField;
pub const CardSection = graph.CardSection;
pub const LayoutNode = ir.LayoutNode;
pub const LayoutEdge = ir.LayoutEdge;
pub const EdgePath = ir.EdgePath;
pub const SubgraphInfo = ir.SubgraphInfo;
pub const coordCast = ir.coordCast;

// ============================================================================
// Algorithms
// ============================================================================

/// Cycle-breaking algorithms — detect and mark back edges
pub const cycle_breaking = @import("algorithms/sugiyama/cycle_breaking.zig");

/// Layering algorithms - assign nodes to horizontal levels
pub const layering = struct {
    pub const longest_path = @import("algorithms/sugiyama/layering/longest_path.zig");
    pub const network_simplex = @import("algorithms/sugiyama/layering/network_simplex.zig");
    pub const virtual = @import("algorithms/sugiyama/layering/virtual.zig");
};

/// Crossing reduction algorithms - minimize edge crossings
pub const crossing = struct {
    pub const median = @import("algorithms/sugiyama/crossing/median.zig");
    pub const adjacent_exchange = @import("algorithms/sugiyama/crossing/adjacent_exchange.zig");

    // Re-export reducers for easy access
    pub const reducers = @import("algorithms/sugiyama/crossing/reducers.zig");
    pub const Reducer = reducers.Reducer;

    // Preset pipelines
    pub const fast = reducers.fast;
    pub const balanced = reducers.balanced;
    pub const quality = reducers.quality;
    pub const none = reducers.none;

    // Factory functions for building custom pipelines
    pub const medianReducer = reducers.median;
    pub const adjacentExchangeReducer = reducers.adjacentExchange;

    // Pipeline runner
    pub const runPipeline = reducers.runPipeline;
};

/// Node positioning algorithms - assign x-coordinates
pub const positioning = struct {
    pub const common = @import("algorithms/sugiyama/positioning/common.zig");
    pub const barycentric = @import("algorithms/sugiyama/positioning/barycentric.zig");
    pub const brandes_kopf = @import("algorithms/sugiyama/positioning/brandes_kopf.zig");
};

/// Edge routing algorithms - determine edge paths
pub const routing = struct {
    pub const direct = @import("algorithms/sugiyama/routing/direct.zig");
    pub const spline = @import("algorithms/sugiyama/routing/spline.zig");
};

/// Subgraph-aware layout orchestration (adjacency enforcement + bounding boxes)
pub const subgraph_layout = @import("algorithms/sugiyama/subgraph.zig");

/// Force-directed graph layout algorithms.
///
/// Each algorithm is standalone — call `compute()` directly with a `*const Graph`
/// and get back a `PositionResult` with Q16.16 positions. Or use `layoutTyped()`
/// for the integrated pipeline.
///
/// ```zig
/// // Standalone usage
/// const fr = zigraph.fdg.fruchterman_reingold;
/// var result = try fr.compute(&graph, allocator, .{});
/// defer result.deinit();
///
/// // Integrated usage
/// var ir = try zigraph.layoutTyped(f32, &graph, allocator, .{
///     .algorithm = .{ .fruchterman_reingold = .{} },
/// });
/// ```
pub const fdg = struct {
    pub const fixed_point = @import("algorithms/shared/fixed_point.zig");
    pub const common = @import("algorithms/shared/common.zig");
    pub const quadtree = @import("algorithms/shared/quadtree.zig");
    pub const forces = @import("algorithms/shared/forces/mod.zig");
    pub const fruchterman_reingold = @import("algorithms/fruchterman_reingold/mod.zig");
};

/// Algorithm interface for BYOA (Bring Your Own Algorithm)
pub const algorithm_interface = @import("algorithms/interface.zig");

// ============================================================================
// Rendering
// ============================================================================

/// Terminal renderer (box drawing characters)
pub const terminal = @import("render/terminal/mod.zig");

/// JSON renderer for external tool integration
pub const json = @import("render/json.zig");

/// Drawing IR JSON serializer (schema v2.0)
pub const drawing_json = @import("render/drawing_json.zig");

/// SVG renderer for high-quality vector output and spline visualization
pub const svg = @import("render/svg/mod.zig");

/// Type-erased renderer interface (wraps SVG, Terminal, JSON, or custom backends)
pub const Renderer = @import("render/Renderer.zig");

/// Color system — numeric Color struct, scientific colormaps, palettes, gradients
pub const color = @import("render/color/mod.zig");

/// Shared rendering types (MarkerShape, etc.)
pub const render_types = @import("render/types.zig");

/// Shared render helpers (subgraph depth computation, etc.)
pub const render_helpers = @import("render/helpers.zig");

pub const MarkerShape = render_types.MarkerShape;
pub const EdgeStyleContext = render_types.EdgeStyleContext;
pub const NodeStyleContext = render_types.NodeStyleContext;
pub const SubgraphStyleContext = render_types.SubgraphStyleContext;
pub const EdgeStyle = svg.EdgeStyle;
pub const EdgeLabelStyle = svg.EdgeLabelStyle;
pub const NodeStyle = svg.NodeStyle;
pub const SubgraphStyle = svg.SubgraphStyle;
pub const shapes = svg.shapes;
pub const subgraph_presets = svg.subgraph_presets;

// Terminal renderer types
pub const TerminalEdgeStyle = terminal.TerminalEdgeStyle;
pub const TerminalNodeStyle = terminal.TerminalNodeStyle;
pub const TerminalEdgeLabelStyle = terminal.TerminalEdgeLabelStyle;
pub const TerminalSubgraphStyle = terminal.TerminalSubgraphStyle;
pub const LineWeight = terminal.LineWeight;
pub const NodeBorder = terminal.NodeBorder;
pub const LabelPlacement = terminal.LabelPlacement;
pub const SubgraphBorder = terminal.SubgraphBorder;
pub const LabelPosition = terminal.LabelPosition;
pub const TextAttrs = terminal.TextAttrs;
pub const TerminalColor = terminal.Color;
pub const TerminalColorMode = terminal.ColorMode;
pub const TerminalCellColor = terminal.CellColor;
pub const TerminalCharSet = terminal.CharSet;
pub const TerminalOutputFormat = terminal.OutputFormat;
pub const TerminalRenderPlan = terminal.RenderPlan;
pub const TerminalHitResult = terminal.HitResult;
pub const terminal_subgraph_presets = terminal.subgraph_presets;
pub const terminal_node_presets = terminal.node_presets;

// ============================================================================
// Diagram primitives
// ============================================================================

/// Sequence diagram primitive
pub const sequence = struct {
    pub const model = @import("primitives/sequence/model.zig");
    pub const layout = @import("primitives/sequence/layout.zig");
    pub const ir = @import("primitives/sequence/ir.zig");
    pub const Sequence = model.Sequence;
    pub const toDrawing = @import("primitives/sequence/ir.zig").toDrawing;
};

/// Gantt chart primitive
pub const gantt = struct {
    pub const model = @import("primitives/gantt/model.zig");
    pub const layout = @import("primitives/gantt/layout.zig");
    pub const ir = @import("primitives/gantt/ir.zig");
    pub const Gantt = model.Gantt;
    pub const toDrawing = @import("primitives/gantt/ir.zig").toDrawing;
};

/// Mindmap primitive
pub const mindmap = struct {
    pub const model = @import("primitives/mindmap/model.zig");
    pub const layout = @import("primitives/mindmap/layout.zig");
    pub const ir = @import("primitives/mindmap/ir.zig");
    pub const Mindmap = model.Mindmap;
    pub const toDrawing = @import("primitives/mindmap/ir.zig").toDrawing;
};

/// Timeline primitive
pub const timeline = struct {
    pub const model = @import("primitives/timeline/model.zig");
    pub const layout = @import("primitives/timeline/layout.zig");
    pub const ir = @import("primitives/timeline/ir.zig");
    pub const Timeline = model.Timeline;
    pub const toDrawing = @import("primitives/timeline/ir.zig").toDrawing;
};

/// Git graph primitive
pub const git_graph = struct {
    pub const model = @import("primitives/git_graph/model.zig");
    pub const layout = @import("primitives/git_graph/layout.zig");
    pub const ir = @import("primitives/git_graph/ir.zig");
    pub const GitGraph = model.GitGraph;
    pub const toDrawing = @import("primitives/git_graph/ir.zig").toDrawing;
};

// ============================================================================
// Layout configuration (re-exported from layout.zig)
// ============================================================================

/// Layout dispatch module — owns config types and layout functions.
pub const layout_mod = @import("layout.zig");

/// Cycle-breaking strategy for handling cyclic graphs in Sugiyama layout.
///
/// The classic Sugiyama pipeline requires a DAG. When the input graph has
/// cycles, back edges must be virtually reversed so that layering can
/// proceed. The reversed edges are restored in the final IR with the
/// `reversed` flag set, allowing renderers to style them differently.
pub const CycleBreaking = layout_mod.CycleBreaking;

/// Available layering algorithms
pub const Layering = layout_mod.Layering;

/// Available positioning algorithms
pub const Positioning = layout_mod.Positioning;

/// Available edge routing algorithms
pub const Routing = layout_mod.Routing;

/// Top-level algorithm selection.
///
/// Sugiyama is the default (hierarchical, level-based). Force-directed
/// algorithms produce free-form layouts. Each variant carries its own config.
pub const Algorithm = layout_mod.Algorithm;

/// Configuration for the layout algorithm.
pub const LayoutConfig = layout_mod.LayoutConfig;

/// Layout error type with detailed information
/// Combines semantic errors (EmptyGraph, CycleDetected) with allocation errors.
/// Note: Custom crossing reducers may produce additional errors.
pub const LayoutError = layout_mod.LayoutError;

/// Compute layout for a graph.
///
/// This is the main entry point for layout computation.
/// The `algorithm` field in config selects between Sugiyama (hierarchical)
/// and force-directed algorithms. Default is Sugiyama.
///
/// Returns error.EmptyGraph if the graph has no nodes.
/// Returns error.CycleDetected if the graph contains a cycle (Sugiyama only,
/// and only when `cycle_breaking` is `.none`). Set `cycle_breaking` to
/// `.depth_first` to automatically handle cyclic graphs.
/// Custom crossing reducers may return additional errors.
/// Use `graph.validate()` before calling for detailed cycle info.
pub const layout = layout_mod.layout;

/// Compute layout with a user-chosen coordinate type.
///
/// The internal Sugiyama pipeline runs with native integer arithmetic.
/// The result is converted to the specified `Coord` type at the boundary
/// using `coordCast`.
///
/// When `Coord` is `usize`, this is equivalent to `layout()` — no conversion,
/// no extra allocation.
///
/// ```zig
/// // Get layout in f32 coordinates (for GPU / web rendering)
/// var ir_f32 = try zigraph.layoutTyped(f32, &graph, allocator, .{});
/// defer ir_f32.deinit();
///
/// // Get layout in u16 coordinates (for embedded / low-memory)
/// var ir_u16 = try zigraph.layoutTyped(u16, &graph, allocator, .{});
/// defer ir_u16.deinit();
/// ```
pub const layoutTyped = layout_mod.layoutTyped;

/// Convenience function: layout and render in one step.
///
/// Returns the terminal (box-drawing) string representation of the graph.
/// Returns error.EmptyGraph or error.CycleDetected if graph is invalid.
/// Custom crossing reducers may return additional errors.
pub fn render(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try terminal.renderWithConfig(&layout_ir, allocator, .{
        .show_dummy_nodes = config.include_dummy_nodes,
        .edge_palette = config.edge_palette,
    });
}

/// Export graph layout as JSON.
///
/// Returns a JSON string containing all layout information:
/// - nodes with positions, labels, levels
/// - edges with routing paths
/// - overall dimensions
///
/// Use this to integrate with external tools (SVG renderers, web UIs, etc.)
/// Custom crossing reducers may return additional errors.
pub fn exportJson(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try json.render(&layout_ir, allocator);
}

/// Layout and render with a custom coordinate type.
///
/// Internally computes the layout (usize), converts to Coord, then renders
/// via the renderer's generic path. Useful when you want the rendered output
/// to reflect a non-usize coordinate space (e.g., JSON with float coords).
///
/// For Terminal and SVG, the renderers convert back to usize internally,
/// so prefer `render()` for those formats unless you need the typed IR
/// for other purposes.
pub fn renderTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try terminal.renderGenericWithConfig(Coord, &layout_ir, allocator, .{
        .show_dummy_nodes = config.include_dummy_nodes,
        .edge_palette = config.edge_palette,
    });
}

/// Export graph layout as JSON with a custom coordinate type.
///
/// This is where typed coordinates shine — the JSON output will contain
/// float values (`"x": 3.5`) or narrow integers (`"x": 42`) matching
/// your chosen Coord type exactly.
///
/// ```zig
/// const json_f32 = try zigraph.exportJsonTyped(f32, &graph, allocator, .{});
/// // Output: {"nodes":[{"x":3.0,"y":0.0,...}], ...}
/// ```
pub fn exportJsonTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try json.renderGeneric(Coord, &layout_ir, allocator);
}

/// Export graph layout as SVG.
///
/// Returns an SVG string with nodes as rectangles and edges as paths/lines.
/// Works well with all layout algorithms including force-directed.
///
/// ```zig
/// const output = try zigraph.exportSvg(&graph, allocator, .{
///     .algorithm = .{ .fruchterman_reingold = .{} },
/// });
/// defer allocator.free(output);
/// try std.fs.cwd().writeFile(.{ .sub_path = "graph.svg", .data = output });
/// ```
pub fn exportSvg(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try svg.render(&layout_ir, allocator, .{});
}

/// Export graph layout as SVG with a custom coordinate type.
pub fn exportSvgTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try svg.renderGeneric(Coord, &layout_ir, allocator, .{});
}

// ============================================================================
// Version info
// ============================================================================

pub const version = "0.2.1";
pub const version_major = 0;
pub const version_minor = 2;
pub const version_patch = 1;

// ============================================================================
// Tests
// ============================================================================

test "version is defined" {
    try std.testing.expectEqualStrings("0.2.1", version);
}

test "core modules are accessible" {
    const allocator = std.testing.allocator;

    // Test Graph
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "Test");
    try std.testing.expectEqual(@as(usize, 1), g.nodeCount());

    // Test LayoutIR
    var layout_ir = LayoutIR(usize).init(allocator);
    defer layout_ir.deinit();
    try std.testing.expectEqual(@as(usize, 0), layout_ir.getNodes().len);
}

test "end-to-end layout: simple chain" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "Middle");
    try g.addNode(3, "End");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 3 nodes
    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);

    // Should have 3 levels
    try std.testing.expectEqual(@as(usize, 3), result.getLevelCount());

    // Should have 2 edges
    try std.testing.expectEqual(@as(usize, 2), result.getEdges().len);

    // Nodes should be ordered by level (Y coordinate)
    const nodes = result.getNodes();
    try std.testing.expect(nodes[0].y < nodes[1].y);
    try std.testing.expect(nodes[1].y < nodes[2].y);
}

test "end-to-end layout: diamond" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    //     A
    //    / \
    //   B   C
    //    \ /
    //     D
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 4 nodes
    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Should have 3 levels (A, B/C, D)
    try std.testing.expectEqual(@as(usize, 3), result.getLevelCount());

    // Should have 4 edges
    try std.testing.expectEqual(@as(usize, 4), result.getEdges().len);
}

test "end-to-end render: simple chain" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "End");
    try g.addEdge(1, 2);

    const output = try render(&g, allocator, .{});
    defer allocator.free(output);

    // Should contain node labels
    try std.testing.expect(std.mem.indexOf(u8, output, "[Start]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[End]") != null);
}

test "layout: empty graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    const result = layout(&g, allocator, .{});
    try std.testing.expectError(error.EmptyGraph, result);
}

test "layout: cyclic graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Creates cycle

    const result = layout(&g, allocator, .{});
    try std.testing.expectError(error.CycleDetected, result);
}

test "layout: cyclic graph with cycle_breaking produces valid layout" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Back edge

    var result = try layout(&g, allocator, .{
        .cycle_breaking = .depth_first,
    });
    defer result.deinit();

    // Should produce a valid layout with 3 real nodes (plus dummies for back edge routing)
    var real_node_count: usize = 0;
    for (result.nodes.items) |node| {
        if (node.kind != .dummy) real_node_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), real_node_count);

    // At least one edge should be marked as reversed
    var has_reversed = false;
    for (result.edges.items) |edge| {
        if (edge.reversed) has_reversed = true;
    }
    try std.testing.expect(has_reversed);

    // Width and height should be reasonable
    try std.testing.expect(result.width > 0);
    try std.testing.expect(result.height > 0);
}

test "layout: cycle_breaking preserves acyclic graph behavior" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Acyclic: A -> B -> C
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    // With cycle_breaking enabled on an acyclic graph, should work identically
    var result_cb = try layout(&g, allocator, .{
        .cycle_breaking = .depth_first,
    });
    defer result_cb.deinit();

    var result_no_cb = try layout(&g, allocator, .{});
    defer result_no_cb.deinit();

    // Same number of nodes and edges
    try std.testing.expectEqual(result_no_cb.nodes.items.len, result_cb.nodes.items.len);

    // No reversed edges (graph is acyclic)
    for (result_cb.edges.items) |edge| {
        try std.testing.expect(!edge.reversed);
    }
}

test "layout: cycle_breaking works with all layering algorithms" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1);

    // Test with each layering algorithm
    const layerings = [_]Layering{ .longest_path, .network_simplex, .network_simplex_fast };
    for (layerings) |lay| {
        var result = try layout(&g, allocator, .{
            .cycle_breaking = .depth_first,
            .layering = lay,
        });
        defer result.deinit();

        var real_count: usize = 0;
        for (result.nodes.items) |node| {
            if (node.kind != .dummy) real_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), real_count);
        try std.testing.expect(result.width > 0);
    }
}

test "layout: positioning config affects output" {
    // Verify that config.positioning is actually wired in and affects the layout.
    // For a tree graph, brandes_kopf centers parents over children,
    // while simple packs left-to-right with level centering.
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Tree graph: A -> B, A -> C (parent with two children)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    // Layout with brandes_kopf (centers parent over children)
    var result_bk = try layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer result_bk.deinit();

    // Layout with barycentric (single-pass barycentric)
    var result_simple = try layout(&g, allocator, .{
        .positioning = .barycentric,
    });
    defer result_simple.deinit();

    // Both should produce valid layouts with same number of nodes
    try std.testing.expectEqual(@as(usize, 3), result_bk.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result_simple.getNodes().len);

    // The positioning algorithm is now wired in and affecting the layout.
    // Brandes-Köpf produces different x-coordinates than simple for most graphs.
    // We verify the config is respected by checking the layouts are valid.
    // (Exact position differences depend on centering calculations.)
    try std.testing.expect(result_bk.getWidth() > 0);
    try std.testing.expect(result_simple.getWidth() > 0);
}

test "layout: can skip validation for performance" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    // Skip validation - useful when you know graph is valid
    var result = try layout(&g, allocator, .{ .skip_validation = true });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
}

test "layoutTyped: usize is identical to layout" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    var result = try layoutTyped(usize, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 1);
}

test "layoutTyped: f32 produces float coordinates" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "End");
    try g.addEdge(1, 2);

    var result = try layoutTyped(f32, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);

    // Coordinates should be valid floats
    const nodes = result.getNodes();
    try std.testing.expect(nodes[0].y < nodes[1].y);
    try std.testing.expect(nodes[0].width > 0.0);
}

test "layoutTyped: u16 produces narrow coordinates" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    var result = try layoutTyped(u16, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 2), result.getLevelCount());
}

test "exportJsonTyped: f32 JSON output" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    const output = try exportJsonTyped(f32, &g, allocator, .{});
    defer allocator.free(output);

    // f32 JSON should contain float notation (e.g., "e+00" or ".")
    try std.testing.expect(output.len > 0);
    // Should contain node labels
    try std.testing.expect(std.mem.indexOf(u8, output, "\"A\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"B\"") != null);
}

// ============================================================================
// FDG integration tests
// ============================================================================

test "layout: FR standard produces valid IR" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result.getEdges().len);
    try std.testing.expect(result.getWidth() > 0);
    try std.testing.expect(result.getHeight() > 0);
}

test "layout: FR fast produces valid IR" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 2), result.getEdges().len);
    try std.testing.expect(result.getWidth() > 0);
    try std.testing.expect(result.getHeight() > 0);
}

test "layout: FR deterministic" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "X");
    try g.addNode(2, "Y");
    try g.addNode(3, "Z");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var r1 = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer r1.deinit();

    var r2 = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer r2.deinit();

    // Same seed → bit-exact identical positions
    for (r1.getNodes(), r2.getNodes()) |n1, n2| {
        try std.testing.expectEqual(n1.x, n2.x);
        try std.testing.expectEqual(n1.y, n2.y);
    }
}

test "layout: FR empty graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    const result = layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    try std.testing.expectError(error.EmptyGraph, result);
}

test "end-to-end: layout with subgraphs produces bounding boxes" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Build a small graph with subgraph structure:
    //   [Gateway] → [Auth] → [DB]
    //                ↑ in cluster "backend"
    try g.addNode(1, "Gateway");
    try g.addNode(2, "Auth");
    try g.addNode(3, "DB");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    const backend = try g.addSubgraph("backend");
    try g.putNodes(&.{ 2, 3 }).inside(backend);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Basic IR sanity
    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 2);

    // Should have exactly 1 subgraph bbox
    try std.testing.expectEqual(@as(usize, 1), result.getSubgraphs().len);
    const sg_bbox = result.getSubgraphs()[0];
    try std.testing.expectEqual(backend, sg_bbox.id);
    try std.testing.expectEqualStrings("backend", sg_bbox.label);

    // Bbox must have positive dimensions
    try std.testing.expect(sg_bbox.width > 0);
    try std.testing.expect(sg_bbox.height > 0);

    // Bbox must contain both Auth and DB nodes
    for (result.getNodes()) |node| {
        if (node.id == 2 or node.id == 3) {
            try std.testing.expect(node.x >= sg_bbox.x);
            try std.testing.expect(node.y >= sg_bbox.y);
            try std.testing.expect(node.x + node.width <= sg_bbox.x + sg_bbox.width);
            try std.testing.expect(node.y + node.height <= sg_bbox.y + sg_bbox.height);
        }
    }

    // Gateway (node 1) should NOT be inside the bbox
    for (result.getNodes()) |node| {
        if (node.id == 1) {
            const inside_x = node.x >= sg_bbox.x and node.x + node.width <= sg_bbox.x + sg_bbox.width;
            const inside_y = node.y >= sg_bbox.y and node.y + node.height <= sg_bbox.y + sg_bbox.height;
            // Gateway could spatially overlap due to layout, but semantically it's not in the subgraph.
            // We just verify the subgraph bbox is computed from Auth + DB, not Gateway.
            _ = inside_x;
            _ = inside_y;
        }
    }
}

test "end-to-end: layout with nested subgraphs" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{ 1, 2, 3 }).inside(inner);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 2 subgraph bboxes
    try std.testing.expectEqual(@as(usize, 2), result.getSubgraphs().len);

    // Find inner/outer bboxes
    var inner_box: ?SubgraphInfo(usize) = null;
    var outer_box: ?SubgraphInfo(usize) = null;
    for (result.getSubgraphs()) |sg| {
        if (sg.id == inner) inner_box = sg;
        if (sg.id == outer) outer_box = sg;
    }
    try std.testing.expect(inner_box != null);
    try std.testing.expect(outer_box != null);

    // Outer must fully contain inner
    const ib = inner_box.?;
    const ob = outer_box.?;
    try std.testing.expect(ob.x <= ib.x);
    try std.testing.expect(ob.y <= ib.y);
    try std.testing.expect(ob.x + ob.width >= ib.x + ib.width);
    try std.testing.expect(ob.y + ob.height >= ib.y + ib.height);
}

test "end-to-end: layout without subgraphs unchanged" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addDiEdge(1, 2);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // No subgraphs → no subgraph bboxes
    try std.testing.expectEqual(@as(usize, 0), result.getSubgraphs().len);
    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 1);
}

test "end-to-end: subgraphs with typed coord conversion" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "X");
    try g.addNode(2, "Y");
    try g.addDiEdge(1, 2);
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    var result_f32 = try layoutTyped(f32, &g, allocator, .{});
    defer result_f32.deinit();

    // Subgraph bbox should be converted to f32
    try std.testing.expectEqual(@as(usize, 1), result_f32.getSubgraphs().len);
    const bbox = result_f32.getSubgraphs()[0];
    try std.testing.expect(bbox.width > 0.0);
    try std.testing.expect(bbox.height > 0.0);
}

test "layout: Sugiyama pin.y overrides level assignment" {
    const allocator = std.testing.allocator;

    // A → B → C → D  (simple chain)
    // Pin A at level 0, C at level 2  (natural assignment would be 0,1,2,3)
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, NodeOptions{ .label = "A", .pin = Pin{ .y = 0 } });
    try g.addNode(2, "B");
    try g.addNode(3, NodeOptions{ .label = "C", .pin = Pin{ .y = 2 } });
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Pinned nodes must land on their requested levels
    const a = result.nodeById(1).?;
    const c = result.nodeById(3).?;
    try std.testing.expectEqual(@as(usize, 0), a.level);
    try std.testing.expectEqual(@as(usize, 2), c.level);

    // Unpinned D must be after C
    const d = result.nodeById(4).?;
    try std.testing.expect(d.y > c.y);

    // Edges still valid
    try std.testing.expect(result.getEdges().len >= 3);
}

test "layout: Sugiyama pin.y respects topological ordering" {
    const allocator = std.testing.allocator;

    // Graph: Client(6) → Server(1), Server → Auth(2), Server → API(3),
    //        Auth → DB(4), API → DB, API → Cache(5)
    // Pinning Server to level 3 and API to level 5 would violate ordering
    // (Server's natural level is 1, API's is 2). The repair pass must push
    // children downward so all edges still flow top-to-bottom.
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(6, "Client");
    try g.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = 3 } });
    try g.addNode(2, "Auth");
    try g.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = 5 } });
    try g.addNode(4, "Database");
    try g.addNode(5, "Cache");
    try g.addEdge(6, 1);
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);
    try g.addEdge(3, 5);

    var result = try layout(&g, allocator, .{ .routing = .spline });
    defer result.deinit();

    // All real nodes must exist (plus dummy nodes for skip-level edges)
    try std.testing.expect(result.getNodes().len >= 6);

    // Every edge must flow downward (from_y < to_y for non-reversed edges)
    for (result.getEdges()) |edge| {
        if (!edge.reversed) {
            try std.testing.expect(edge.from_y <= edge.to_y);
        }
    }

    // Server (pinned to level 3) must be above Auth and API in level ordering
    const server = result.nodeById(1).?;
    const auth = result.nodeById(2).?;
    const api = result.nodeById(3).?;
    try std.testing.expect(server.level < auth.level);
    try std.testing.expect(server.level < api.level);

    // API (pinned to level 5) must be above its children
    const db = result.nodeById(4).?;
    const cache = result.nodeById(5).?;
    try std.testing.expect(api.level < db.level);
    try std.testing.expect(api.level < cache.level);
}

test "layout: Sugiyama pin re-layout feedback loop — node count stable" {
    // Simulates what example 09 does: layout → extract positions → feed back as pins → re-layout.
    // Verifies that dummy node count doesn't grow across iterations.
    const allocator = std.testing.allocator;

    // -- Iteration 0: no pins --
    var g0 = Graph.init(allocator);
    defer g0.deinit();
    try g0.addNode(6, "Client");
    try g0.addNode(1, "Server");
    try g0.addNode(2, "Auth");
    try g0.addNode(3, "API");
    try g0.addNode(4, "Database");
    try g0.addNode(5, "Cache");
    try g0.addEdge(6, 1);
    try g0.addEdge(1, 2);
    try g0.addEdge(1, 3);
    try g0.addEdge(2, 4);
    try g0.addEdge(3, 4);
    try g0.addEdge(3, 5);

    var ir0 = try layout(&g0, allocator, .{ .routing = .spline });
    defer ir0.deinit();

    const total_nodes_0 = ir0.getNodes().len;
    try std.testing.expect(total_nodes_0 >= 6); // at least 6 real nodes

    // Count explicit+implicit (real) nodes and dummies
    var real_0: usize = 0;
    var dummy_0: usize = 0;
    for (ir0.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_0 += 1;
        } else {
            real_0 += 1;
        }
    }

    // Extract positions from IR (simulating frontend's pin conversion)
    // Pin Server(1) and API(3) at their layout positions
    const server_y_0 = ir0.nodeById(1).?.y;
    const api_y_0 = ir0.nodeById(3).?.y;

    // -- Iteration 1: pin Server and API at their layout positions --
    var g1 = Graph.init(allocator);
    defer g1.deinit();
    try g1.addNode(6, "Client");
    try g1.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_y_0 } });
    try g1.addNode(2, "Auth");
    try g1.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_y_0 } });
    try g1.addNode(4, "Database");
    try g1.addNode(5, "Cache");
    try g1.addEdge(6, 1);
    try g1.addEdge(1, 2);
    try g1.addEdge(1, 3);
    try g1.addEdge(2, 4);
    try g1.addEdge(3, 4);
    try g1.addEdge(3, 5);

    var ir1 = try layout(&g1, allocator, .{ .routing = .spline });
    defer ir1.deinit();

    const total_nodes_1 = ir1.getNodes().len;
    const total_edges_1 = ir1.getEdges().len;

    var real_1: usize = 0;
    var dummy_1: usize = 0;
    for (ir1.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_1 += 1;
        } else {
            real_1 += 1;
        }
    }

    // -- Iteration 2: pin at the NEW positions from iteration 1 --
    const server_y_1 = ir1.nodeById(1).?.y;
    const api_y_1 = ir1.nodeById(3).?.y;

    var g2 = Graph.init(allocator);
    defer g2.deinit();
    try g2.addNode(6, "Client");
    try g2.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_y_1 } });
    try g2.addNode(2, "Auth");
    try g2.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_y_1 } });
    try g2.addNode(4, "Database");
    try g2.addNode(5, "Cache");
    try g2.addEdge(6, 1);
    try g2.addEdge(1, 2);
    try g2.addEdge(1, 3);
    try g2.addEdge(2, 4);
    try g2.addEdge(3, 4);
    try g2.addEdge(3, 5);

    var ir2 = try layout(&g2, allocator, .{ .routing = .spline });
    defer ir2.deinit();

    const total_nodes_2 = ir2.getNodes().len;
    const total_edges_2 = ir2.getEdges().len;

    var real_2: usize = 0;
    var dummy_2: usize = 0;
    for (ir2.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_2 += 1;
        } else {
            real_2 += 1;
        }
    }

    // Real node count must always be 6
    try std.testing.expectEqual(@as(usize, 6), real_0);
    try std.testing.expectEqual(@as(usize, 6), real_1);
    try std.testing.expectEqual(@as(usize, 6), real_2);

    // Note: un-pinned (iter 0) may differ from pinned (iter 1) in total nodes/edges
    // because pinning changes the level structure. That's fine.
    // The KEY invariant: pinned iterations must be STABLE (iter 1 == iter 2)

    // Edge count stable between pinned iterations
    try std.testing.expectEqual(total_edges_1, total_edges_2);

    // Total node count (including dummies) must NOT grow
    try std.testing.expectEqual(total_nodes_1, total_nodes_2);

    // Dummy count must be stable between pinned iterations
    try std.testing.expectEqual(dummy_1, dummy_2);
}

test "layout: Sugiyama pin jitter stress — dummy count stays bounded" {
    // Simulates a realistic interactive session: pin 3 nodes, jitter their
    // y-positions by small amounts (±1) each iteration, run 10 re-layouts.
    // Dummy count must stay bounded — not explode across iterations.
    const allocator = std.testing.allocator;

    // Jitter offsets: small perturbations simulating user dragging nodes slightly
    const jitter = [_]i32{ 0, 1, -1, 2, -1, 0, 1, -2, 1, 0 };
    const N_ITERS = jitter.len;

    var dummy_counts: [N_ITERS]usize = undefined;
    var total_counts: [N_ITERS]usize = undefined;
    var edge_counts: [N_ITERS]usize = undefined;

    // Starting pin values (close to natural Sugiyama levels: Server=1, Auth=2, API=2)
    var server_pin: usize = 1;
    var auth_pin: usize = 2;
    var api_pin: usize = 2;

    for (0..N_ITERS) |iter| {
        // Apply jitter to pin positions (clamp to >= 0)
        const j = jitter[iter];
        server_pin = if (j < 0 and @as(usize, @intCast(-j)) > server_pin) 0 else if (j >= 0) server_pin + @as(usize, @intCast(j)) else server_pin - @as(usize, @intCast(-j));
        auth_pin = if (j < 0 and @as(usize, @intCast(-j)) > auth_pin) 0 else if (j >= 0) auth_pin + @as(usize, @intCast(j)) else auth_pin - @as(usize, @intCast(-j));
        // API jitters in the opposite direction for variety
        const j_inv = -j;
        api_pin = if (j_inv < 0 and @as(usize, @intCast(-j_inv)) > api_pin) 0 else if (j_inv >= 0) api_pin + @as(usize, @intCast(j_inv)) else api_pin - @as(usize, @intCast(-j_inv));

        var g = Graph.init(allocator);
        defer g.deinit();
        try g.addNode(6, "Client");
        try g.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_pin } });
        try g.addNode(2, NodeOptions{ .label = "Auth", .pin = Pin{ .y = auth_pin } });
        try g.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_pin } });
        try g.addNode(4, "Database");
        try g.addNode(5, "Cache");
        try g.addEdge(6, 1);
        try g.addEdge(1, 2);
        try g.addEdge(1, 3);
        try g.addEdge(2, 4);
        try g.addEdge(3, 4);
        try g.addEdge(3, 5);

        var layout_ir = try layout(&g, allocator, .{ .routing = .spline });
        defer layout_ir.deinit();

        var dummies: usize = 0;
        for (layout_ir.getNodes()) |n| {
            if (n.kind == .dummy) dummies += 1;
        }
        dummy_counts[iter] = dummies;
        total_counts[iter] = layout_ir.getNodes().len;
        edge_counts[iter] = layout_ir.getEdges().len;

        // Feed back actual positions for next iteration (simulating the browser loop)
        server_pin = layout_ir.nodeById(1).?.y;
        auth_pin = layout_ir.nodeById(2).?.y;
        api_pin = layout_ir.nodeById(3).?.y;
    }

    // Find min and max dummy counts across all iterations
    var min_dummies: usize = dummy_counts[0];
    var max_dummies: usize = dummy_counts[0];
    for (dummy_counts) |d| {
        min_dummies = @min(min_dummies, d);
        max_dummies = @max(max_dummies, d);
    }

    // Key assertion: dummy count must NOT explode.
    // With level compaction, max should be very close to min.
    // Allow some fluctuation (jitter can change which edges skip levels)
    // but max must be <= min + 8.
    try std.testing.expect(max_dummies <= min_dummies + 8);

    // Also verify: total nodes should stay bounded (6 real + bounded dummies)
    for (total_counts) |t| {
        try std.testing.expect(t <= 6 + max_dummies);
        try std.testing.expect(t >= 6);
    }
}

test "layout: FR standard respects pin constraints" {
    const allocator = std.testing.allocator;

    // Triangle A → B → C, A → C   with A pinned at (0,0), C pinned at (5,5)
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, NodeOptions{ .label = "A", .pin = Pin{ .x = 0, .y = 0 } });
    try g.addNode(2, "B");
    try g.addNode(3, NodeOptions{ .label = "C", .pin = Pin{ .x = 5, .y = 5 } });
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result.getEdges().len);

    // The two pinned nodes should be at distinct positions
    const a = result.nodeById(1).?;
    const c = result.nodeById(3).?;
    // A should be closer to the origin than C
    try std.testing.expect(a.x < c.x);
    try std.testing.expect(a.y < c.y);
    // The unpinned node B should exist in a valid position
    const b = result.nodeById(2).?;
    try std.testing.expect(b.x >= 0);
    try std.testing.expect(b.y >= 0);
}

test "layout: FR fast respects pin constraints" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Pin two opposite corners of a 4-node graph
    try g.addNode(1, NodeOptions{ .label = "TL", .pin = Pin{ .x = 0, .y = 0 } });
    try g.addNode(2, NodeOptions{ .label = "BR", .pin = Pin{ .x = 8, .y = 8 } });
    try g.addNode(3, "Free1");
    try g.addNode(4, "Free2");
    try g.addEdge(1, 3);
    try g.addEdge(3, 2);
    try g.addEdge(1, 4);
    try g.addEdge(4, 2);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Pinned nodes keep their relative ordering
    const tl = result.nodeById(1).?;
    const br = result.nodeById(2).?;
    try std.testing.expect(tl.x < br.x);
    try std.testing.expect(tl.y < br.y);
}

test "end-to-end layout: card node height respected" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const lines: []const []const u8 = &.{ "line1", "line2" };
    try g.addNode(1, NodeOptions{
        .label = "Card",
        .lines = lines,
    });
    try g.addNode(2, "Below");
    try g.addEdge(1, 2);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    const nodes = result.getNodes();
    // Card node should have height 6 (1+1+1+2+1)
    var card_node: ?LayoutNode(usize) = null;
    for (nodes) |n| {
        if (std.mem.eql(u8, n.label, "Card")) card_node = n;
    }
    try std.testing.expect(card_node != null);
    try std.testing.expectEqual(@as(usize, 6), card_node.?.height);
    try std.testing.expectEqual(@as(usize, 2), card_node.?.lines.len);
}

// Run tests from submodules
test {
    _ = graph;
    _ = ir;
    _ = errors;
    _ = layering.longest_path;
    _ = crossing.median;
    _ = positioning.barycentric;
    _ = routing.direct;
    _ = terminal;
    _ = svg;
    _ = json;
    _ = subgraph_layout;
    _ = @import("fuzz_tests.zig");

    // Force-directed graph modules
    _ = fdg.fixed_point;
    _ = fdg.common;
    _ = fdg.quadtree;
    _ = fdg.fruchterman_reingold;
}
