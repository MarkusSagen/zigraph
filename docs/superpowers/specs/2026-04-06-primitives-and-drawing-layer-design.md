# Primitives & Drawing Layer Design Spec

## Goal

Extend zigraph from a graph-only layout engine into a multi-primitive diagramming toolkit supporting flowcharts, ER diagrams, class diagrams, state diagrams, network topology, C4 architecture, sequence diagrams, Gantt charts, timelines, mindmaps, and git graphs — while preserving backwards compatibility and the zero-dependency constraint.

## Architecture

### Current State

```
Graph → Sugiyama/FDG → LayoutIR → Terminal/SVG/JSON
Tree → standalone renderer (no IR)
```

### Target State

A new **DrawingIR** layer sits between layout and rendering. Every primitive type produces DrawingIR. Existing renderers are extended to consume DrawingIR.

```
Graph ────→ Sugiyama/FDG ──→ LayoutIR ──→ DrawingIR ──→ Terminal/SVG/JSON
Sequence ──→ SequenceLayout ──→ SequenceIR ──→ DrawingIR ──→ Terminal/SVG/JSON
Gantt ────→ GanttLayout ────→ GanttIR ────→ DrawingIR ──→ Terminal/SVG/JSON
Mindmap ──→ RadialLayout ──→ MindmapIR ──→ DrawingIR ──→ Terminal/SVG/JSON
GitGraph ──→ LaneLayout ───→ GitGraphIR ──→ DrawingIR ──→ Terminal/SVG/JSON
Timeline ──→ TimelineLayout → TimelineIR ──→ DrawingIR ──→ Terminal/SVG/JSON
```

Backwards compatibility: existing `terminal.render(layout_ir)` and `svg.render(layout_ir)` keep working. Internally they call `layout_ir.toDrawingIR()` then render the DrawingIR.

### Zig API Style

All primitives follow idiomatic Zig: structs + init/deinit + method calls with explicit allocator passing and per-call error handling. Matches the existing `Graph.init` / `g.addNode` / `g.addEdge` pattern.

---

## DrawingIR

The shared intermediate representation consumed by all renderers.

### Primitives

| Type | Fields | Purpose |
|------|--------|---------|
| `Rect` | x, y, width, height, corner_radius, fill, border_style, border_weight | Rectangles, rounded rects |
| `Circle` | cx, cy, radius, fill, border_style | Dots, commit nodes, actor heads |
| `Ellipse` | cx, cy, rx, ry, fill, border_style | Oval shapes |
| `Arc` | cx, cy, radius, start_angle, end_angle, fill, border_style | Pie segments, self-loops |
| `Polygon` | points ([]Point), fill, border_style | Diamonds, hexagons, trapezoids, arrows |
| `Line` | x1, y1, x2, y2, style (solid/dashed/dotted/bold), weight, start_marker, end_marker | Simple connections |
| `Path` | points ([]Point), is_spline, style, weight, start_marker, end_marker | Multi-segment lines, curves |
| `Text` | x, y, content, alignment (left/center/right), style (normal/bold/dim/italic/underline), font_size | Labels, titles |
| `Group` | children ([]DrawingPrimitive), label, border_style, x, y, width, height | Containers, swimlanes, fragments |

### Marker Types

`none`, `arrow`, `hollow_arrow`, `diamond`, `hollow_diamond`, `circle`, `crow_foot_one`, `crow_foot_many`, `crow_foot_zero_one`, `crow_foot_zero_many`

### Style Types

- `BorderStyle`: solid, dashed, dotted, double, bold, none
- `Fill`: color (RGB), none, gradient (start_color, end_color, direction)
- `TextStyle`: normal, bold, dim, italic, underline (composable flags)

### Conversion

`LayoutIR.toDrawingIR()` converts existing graph layout results into DrawingIR:
- Each LayoutNode → Rect (or shape-appropriate primitive) + Text for label
- Each LayoutEdge → Path with appropriate markers
- Each SubgraphInfo → Group with border

---

## Phase 1: Graph Engine Extensions

These extend the existing `Graph` + `LayoutIR` pipeline with richer options. No new layout engines.

### 1. Node Shapes

Add `shape: NodeShape` to `NodeOptions`:

```zig
pub const NodeShape = enum {
    rect,           // default — ┌──┐│  │└──┘
    rounded_rect,   // ╭──╮│  │╰──╯
    diamond,        //   /\  /  \  \  /   \/
    parallelogram,  //  /    /  /    /
    cylinder,       // ═══╕ │   │ ═══╛
    stadium,        // (  label  )
    circle,         // (label)
    hexagon,        //  / \|   |\ /
    trapezoid,      //  /      \|        |
    double_circle,  // ((label)) — state start/end
    subroutine,     // ║ label ║ — subprocess
    asymmetric,     // > label ]
};
```

Terminal renderer: approximates shapes with box-drawing and ASCII art.
SVG renderer: emits actual geometric shapes using Polygon/Circle/Ellipse drawing primitives.

Shape vertex generation lives in `src/core/shapes.zig` — given a shape enum, width, height, and center point, returns polygon vertices (or circle/ellipse parameters).

### 2. Edge Decorators

Add to edge options:

```zig
pub const EdgeDecorator = struct {
    line_style: LineStyle = .solid,    // solid, dashed, dotted, bold
    start_marker: MarkerType = .none,
    end_marker: MarkerType = .arrow,
};

pub const MarkerType = enum {
    none,
    arrow,
    hollow_arrow,
    diamond,
    hollow_diamond,
    circle,
    crow_foot_one,
    crow_foot_many,
    crow_foot_zero_one,
    crow_foot_zero_many,
};
```

### 3. Card Node Extensions

Extend the existing card node with sections:

```zig
pub const CardSection = struct {
    title: ?[]const u8 = null,      // optional section header
    fields: []const CardField,
};

pub const CardField = struct {
    name: []const u8,
    type_name: ?[]const u8 = null,  // for ER: "VARCHAR(255)"
    visibility: Visibility = .none, // for class: +, -, #
    constraints: []const Constraint = &.{}, // PK, FK, NOT NULL
};

pub const Visibility = enum { none, public, private, protected };
pub const Constraint = enum { pk, fk, not_null, unique, auto_increment };
```

Card nodes render as multi-section boxes:
```
┌─────────────┐
│   users      │  ← header
├─────────────┤
│ + id: INT PK │  ← fields section
│ + name: TEXT  │
│ - email: TEXT │
├─────────────┤
│ + validate() │  ← methods section (class diagrams)
└─────────────┘
```

### 4. Subgraph Styling

Add `style` to subgraph options:

```zig
pub const SubgraphStyle = enum {
    default,    // solid border
    dashed,     // dashed border
    cloud,      // cloud shape (SVG) / dashed with rounded corners (terminal)
    zone,       // shaded background region
    system,     // C4 system boundary — bold border
    container,  // C4 container boundary — dashed border
    component,  // C4 component boundary — dotted border
};
```

### 5. Preset Configs

High-level presets combining shapes, decorators, and styling:

```zig
pub const presets = struct {
    // Existing
    pub fn sugiyama_fast() LayoutConfig { ... }
    pub fn sugiyama_standard() LayoutConfig { ... }
    pub fn sugiyama_quality() LayoutConfig { ... }
    pub fn fdg_standard() LayoutConfig { ... }
    pub fn fdg_fast() LayoutConfig { ... }

    // New
    pub fn flowchart() LayoutConfig { ... }      // rounded rects, directional edges
    pub fn er_diagram() LayoutConfig { ... }      // card nodes, crow's foot
    pub fn class_diagram() LayoutConfig { ... }   // card sections, relationship arrows
    pub fn state_diagram() LayoutConfig { ... }   // double-circle start/end, self-loops
    pub fn network() LayoutConfig { ... }         // labeled nodes, cloud subgraphs
    pub fn c4_context() LayoutConfig { ... }      // system-style subgraphs
    pub fn c4_container() LayoutConfig { ... }    // container-style subgraphs
    pub fn c4_component() LayoutConfig { ... }    // component-style subgraphs
};
```

---

## Phase 2: New Primitive Types

Each primitive has its own data model, layout algorithm, and typed IR.

### 7. Sequence Diagram

**Data model:**

```zig
pub const Sequence = struct {
    actors: std.ArrayListUnmanaged(Actor),
    messages: std.ArrayListUnmanaged(Message),
    fragments: std.ArrayListUnmanaged(Fragment),

    pub fn init(allocator: Allocator) Sequence { ... }
    pub fn deinit(self: *Sequence) void { ... }
    pub fn addActor(self: *Sequence, name: []const u8, opts: ActorOptions) !ActorId { ... }
    pub fn addMessage(self: *Sequence, from: ActorId, to: ActorId, text: []const u8, opts: MessageOptions) !void { ... }
    pub fn addFragment(self: *Sequence, kind: FragmentKind, messages: []const MessageId, label: []const u8) !void { ... }
};

pub const ActorOptions = struct {
    type: ActorType = .participant,  // participant, actor, database, queue, boundary
};

pub const MessageOptions = struct {
    style: MessageStyle = .sync,     // sync, async, return, create, destroy
    activate: bool = false,
    deactivate: bool = false,
};

pub const FragmentKind = enum { loop, alt, opt, par, @"break", critical, ref };
```

**Layout algorithm:**
- Actors placed left-to-right with configurable spacing, order follows declaration
- Messages placed top-to-bottom with fixed vertical step
- Lifelines: vertical dashed lines from actor box to bottom
- Activation boxes: nested rectangles on lifelines between activate/deactivate
- Self-messages: arc looping back to same actor
- Fragments: bordered rectangles spanning the messages they contain
- Total width: `(actor_count - 1) * actor_spacing + margins`
- Total height: `header_height + message_count * message_spacing + footer`

**SequenceIR → DrawingIR mapping:**
- Actor boxes → Rect + Text
- Actor icons (for actor type) → Circle + Line (stick figure) or Rect (database)
- Lifelines → Line (dashed)
- Messages → Line + Text + optional markers (arrow, open arrow, dashed)
- Activation boxes → Rect (thin, filled)
- Fragments → Group with border + Text label
- Self-messages → Arc + Text

### 8. Gantt Chart

**Data model:**

```zig
pub const Gantt = struct {
    title: ?[]const u8,
    date_format: DateFormat,
    sections: std.ArrayListUnmanaged(Section),
    tasks: std.ArrayListUnmanaged(Task),
    milestones: std.ArrayListUnmanaged(Milestone),
    excludes: ExcludeConfig,

    pub fn init(allocator: Allocator, opts: GanttOptions) Gantt { ... }
    pub fn deinit(self: *Gantt) void { ... }
    pub fn addSection(self: *Gantt, name: []const u8) !SectionId { ... }
    pub fn addTask(self: *Gantt, name: []const u8, opts: TaskOptions) !TaskId { ... }
    pub fn addMilestone(self: *Gantt, name: []const u8, opts: MilestoneOptions) !MilestoneId { ... }
};

pub const TaskOptions = struct {
    start: ?Date = null,           // explicit start date
    after: ?TaskId = null,         // start after this task ends
    duration_days: u32,
    progress: u8 = 0,             // 0-100 percent
    is_critical: bool = false,
    section: ?SectionId = null,
};

pub const MilestoneOptions = struct {
    date: ?Date = null,
    after: ?TaskId = null,
};

pub const ExcludeConfig = struct {
    weekends: bool = false,
    dates: []const Date = &.{},
};

pub const DateFormat = enum { iso, us, eu };

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,
};
```

**Layout algorithm:**
- Time axis: horizontal, spanning from earliest start to latest end
- Granularity: auto-select day/week/month based on total span
- Tasks: horizontal bars positioned at their row, width proportional to duration
- Dependencies: arrows from end of predecessor to start of successor
- Milestones: diamond markers at their date
- Sections: labeled row groups with separator lines
- Excluded dates: gaps or compressed regions in the time axis
- Critical path: tasks marked `is_critical` get highlighted styling

**GanttIR → DrawingIR mapping:**
- Time axis → Line + Text labels (dates)
- Grid lines → Line (dotted, vertical)
- Tasks → Rect (filled proportional to progress) + Text label
- Dependencies → Path with arrow
- Milestones → Polygon (diamond)
- Section headers → Text (bold) + Line separator
- Today marker → Line (dashed, vertical, highlighted)

### 9. Timeline

**Data model:**

```zig
pub const Timeline = struct {
    title: ?[]const u8,
    events: std.ArrayListUnmanaged(Event),
    periods: std.ArrayListUnmanaged(Period),

    pub fn init(allocator: Allocator, opts: TimelineOptions) Timeline { ... }
    pub fn deinit(self: *Timeline) void { ... }
    pub fn addEvent(self: *Timeline, title: []const u8, date: Date, opts: EventOptions) !void { ... }
    pub fn addPeriod(self: *Timeline, title: []const u8, start: Date, end: Date) !void { ... }
};

pub const EventOptions = struct {
    description: ?[]const u8 = null,
    group: ?[]const u8 = null,
};
```

**Layout algorithm:**
- Horizontal time axis with auto-scaled intervals
- Events as labeled markers (circle + vertical line to axis + text)
- Events alternate above/below the axis to avoid overlap
- Periods as horizontal bars above the axis
- Groups as swim lanes if specified

**TimelineIR → DrawingIR mapping:**
- Time axis → Line + Text labels
- Events → Circle + Line + Text
- Periods → Rect + Text
- Groups → Group with label

### 10. Mindmap

**Data model:**

```zig
pub const Mindmap = struct {
    root: ?MindNodeId,
    nodes: std.ArrayListUnmanaged(MindNode),

    pub fn init(allocator: Allocator) Mindmap { ... }
    pub fn deinit(self: *Mindmap) void { ... }
    pub fn addNode(self: *Mindmap, text: []const u8, opts: MindNodeOptions) !MindNodeId { ... }
    pub fn addChild(self: *Mindmap, parent: MindNodeId, child: MindNodeId) !void { ... }
    pub fn setRoot(self: *Mindmap, node: MindNodeId) void { ... }
};

pub const MindNodeOptions = struct {
    shape: MindShape = .rounded_rect,  // rounded_rect, rect, circle, cloud, bang, hexagon
    color: ?Color = null,
};
```

**Layout algorithm — Radial Tree:**
1. Compute subtree weights (leaf count per subtree)
2. Root at center (0, 0)
3. Divide 360 degrees among root's children proportional to subtree weight
4. Each child placed at distance `level * ring_spacing` from center, at center of its angular sector
5. Recurse: each child's subtree gets its allocated angular range
6. Edge routing: straight lines or gentle curves from parent to child
7. Collision detection: if nodes overlap, expand ring spacing

**MindmapIR → DrawingIR mapping:**
- Nodes → Rect/Circle/Polygon (per shape) + Text
- Edges → Path (curved line from parent center to child center)
- Root node → larger Rect/Ellipse with bold border

### 11. Git Graph

**Data model:**

```zig
pub const GitGraph = struct {
    commits: std.ArrayListUnmanaged(Commit),
    branches: std.ArrayListUnmanaged(Branch),

    pub fn init(allocator: Allocator) GitGraph { ... }
    pub fn deinit(self: *GitGraph) void { ... }
    pub fn addBranch(self: *GitGraph, name: []const u8, opts: BranchOptions) !BranchId { ... }
    pub fn addCommit(self: *GitGraph, branch: BranchId, opts: CommitOptions) !CommitId { ... }
    pub fn merge(self: *GitGraph, from: BranchId, into: BranchId, opts: CommitOptions) !CommitId { ... }
    pub fn cherryPick(self: *GitGraph, commit: CommitId, into: BranchId) !CommitId { ... }
};

pub const BranchOptions = struct {
    from_branch: ?BranchId = null,  // fork from this branch's HEAD
    color: ?Color = null,
};

pub const CommitOptions = struct {
    message: ?[]const u8 = null,
    tag: ?[]const u8 = null,
    id: ?[]const u8 = null,        // custom short hash display
};
```

**Layout algorithm — Lane-based:**
1. Assign each branch a lane (vertical column), ordered by creation time
2. Commits placed top-to-bottom in chronological order
3. Main/first branch gets lane 0 (leftmost)
4. Merge commits connect across lanes with diagonal/curved lines
5. Cherry-picks shown as dashed lines across lanes
6. Branch labels positioned at the branch's first commit
7. Tags positioned next to their commit

**GitGraphIR → DrawingIR mapping:**
- Commits → Circle (small filled dot) + Text (message)
- Branch lanes → Line (vertical, colored per branch)
- Merge lines → Path (diagonal from source lane to target lane)
- Cherry-pick lines → Path (dashed diagonal)
- Branch labels → Rect (rounded, colored) + Text
- Tags → Polygon (flag/pennant shape) + Text

---

## Project Structure Changes

### Monorepo, Single Package

Everything stays in one repo and one `build.zig.zon` package. The library is importable as `@import("zigraph")`.

### root.zig Refactor

Split the 2686-line `root.zig` into:
- `root.zig` — thin re-export layer (~100 lines), public API surface
- `layout.zig` — layout dispatch logic (algorithm selection, validation, pipeline orchestration)

### New Directory: `src/drawing/`

```
src/drawing/
├── ir.zig      — DrawingIR types (Rect, Circle, Ellipse, Arc, Polygon, Line, Path, Text, Group)
└── convert.zig — LayoutIR → DrawingIR conversion
```

### New Directory: `src/primitives/`

```
src/primitives/
├── sequence/
│   ├── model.zig
│   ├── layout.zig
│   ├── ir.zig
│   └── tests.zig
├── gantt/
│   ├── model.zig
│   ├── layout.zig
│   ├── ir.zig
│   └── tests.zig
├── timeline/
│   ├── model.zig
│   ├── layout.zig
│   ├── ir.zig
│   └── tests.zig
├── mindmap/
│   ├── model.zig
│   ├── layout.zig
│   ├── ir.zig
│   └── tests.zig
└── git_graph/
    ├── model.zig
    ├── layout.zig
    ├── ir.zig
    └── tests.zig
```

### Extended Existing Files

- `src/core/graph.zig` — add `NodeShape`, `EdgeDecorator` to options structs
- `src/core/shapes.zig` — new file, shape vertex generation
- `src/presets.zig` — add flowchart, ER, class, state, network, C4 presets
- `src/render/terminal/mod.zig` — add `renderDrawing(DrawingIR)` entry point
- `src/render/svg/mod.zig` — add `renderDrawing(DrawingIR)` entry point
- `src/render/json.zig` — add DrawingIR serialization (schema v2.0)

---

## Rendering Strategy

### Terminal Renderer (Unicode/ASCII)

| Drawing Primitive | Terminal Representation |
|---|---|
| Rect | Box-drawing: `┌─┐│└─┘`, rounded: `╭─╮│╰─╯` |
| Circle | `( label )` or `●` for small dots |
| Ellipse | Same as circle approximation |
| Arc | `╭╮╰╯` curved corners, fallback to `┌┐└┘` |
| Polygon | Per-shape ASCII art: diamond `/\ \/`, hexagon `/ \| |\ /` |
| Line | `│`, `─`, junction merging via existing infrastructure |
| Path | Multi-segment lines using existing edge painting |
| Text | Direct placement with ANSI styling (bold, dim, italic, underline) |
| Group | Optional border box around children |

### SVG Renderer

Direct 1:1 mapping: Rect→`<rect>`, Circle→`<circle>`, Ellipse→`<ellipse>`, Arc→`<path>` with arc commands, Polygon→`<polygon>`, Line→`<line>`, Path→`<path>`, Text→`<text>`, Group→`<g>`.

### JSON Renderer

- Schema v2.0 for DrawingIR output
- Schema v1.2 preserved for backwards-compatible LayoutIR output
- Each drawing primitive → JSON object with `type`, position, dimensions, style fields

### Backwards Compatibility

- `terminal.render(layout_ir)` and `svg.render(layout_ir)` keep working unchanged
- New entry points: `terminal.renderDrawing(drawing_ir)`, `svg.renderDrawing(drawing_ir)`
- Old path internally: `layout_ir.toDrawingIR()` → `renderDrawing()`

---

## Testing Strategy

**Per-primitive tests** in `primitives/<name>/tests.zig`:
- Model construction and validation
- Layout correctness (positions, dimensions, ordering)
- IR conversion to DrawingIR
- Edge cases: empty input, single element, dependency cycles (gantt)

**DrawingIR tests** in `drawing/tests.zig`:
- `LayoutIR.toDrawingIR()` correctness
- Snapshot tests: known DrawingIR → terminal/SVG output string comparison

**Phase 1 tests:**
- Extend `render/terminal/render_tests.zig` and `render/svg/render_tests.zig` for new shapes and decorators
- Shape vertex generation in `core/shapes.zig` tests

**Integration tests** per primitive:
- Full pipeline: construct model → layout → DrawingIR → terminal string → comparison
- Located in each primitive's `tests.zig`

All tests are pure computation, no mocking, deterministic.

---

## Implementation Order

1. DrawingIR types + LayoutIR→DrawingIR conversion
2. Node shapes + polygon vertex generation (`core/shapes.zig`)
3. Edge decorators (crow's foot, diamonds, etc.)
4. Card node extensions (sections, field types, constraints)
5. Subgraph styling (C4, cloud, zone)
6. Terminal DrawingIR renderer (`terminal.renderDrawing`)
7. SVG DrawingIR renderer (`svg.renderDrawing`)
8. JSON DrawingIR serializer (schema v2.0)
9. Preset configs (flowchart, ER, class, state, network, C4)
10. Sequence diagram (model + layout + IR)
11. Gantt chart (model + layout + IR)
12. Mindmap (model + radial tree layout + IR)
13. Timeline (model + layout + IR)
14. Git graph (model + lane layout + IR)
15. root.zig refactor — extract layout.zig, re-export all new types

---

## Out of Scope

- DSL parser (sub-project #3)
- CLI tool (sub-project #4)
- Justfile and CI pipeline (sub-project #5)
- Docs site updates (sub-project #6)
- Category C visualizations (pie, waterfall, burndown, sankey — possible future work)
- Phase 3 primitives (kanban, WBS, quadrant, grid layout — possible future work)
