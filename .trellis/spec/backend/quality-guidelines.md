# Quality Guidelines

> Code quality standards for the ShowKeys project (Zig + Cairo + Wayland rendering).

---

## Overview

ShowKeys is a system-level Wayland utility. Code quality focuses on:
- **No dead code** — unused files/fields/functions must be removed proactively
- **No module-level global state** — all mutable state must belong to a struct (`App`, `RenderModState`, etc.)
- **No per-frame allocation** — hot paths (render, animation) must reuse allocations
- **Single rendering pipeline** — one active render path, not two

---

## Forbidden Patterns

### Module-level mutable globals

```zig
// BAD: global mutable state outside a struct
var layout_arena: std.heap.ArenaAllocator = undefined;
pub var shift_active: bool = false;
```

**Why**: Global state makes ownership unclear, prevents proper cleanup, and breaks testability. Always move to a struct field (e.g. `RenderModState`, `App`).

### Dead code left in tree

```zig
// BAD: unused function left in codebase
pub fn renderKeycapsToCairo(...) void { ... }
```

**Why**: Unused code creates false expectations, wastes compile time, and misleads readers. If it's unused, delete it.

### Save/restore hacks on struct fields

```zig
// BAD: temporarily mutate a field then restore
const layout_x_saved = layout.x;
layout.x = draw_x;
// ... use layout.x ...
layout.x = layout_x_saved;
```

**Why**: Creates subtle bugs, confuses readers, and indicates a poor abstraction. Pass values as parameters instead of mutating struct fields.

### Two competing implementations of the same flow

```zig
// BAD: render.zig and render_mod.zig both have renderFrame()
```

**Why**: Ambiguity about which path is active. One source of truth only.

---

## Required Patterns

### One rendering pipeline via event bus

The app must have exactly one active rendering module (`render_mod.zig`). Legacy paths must be removed when superseded.

```zig
// Render module subscribes to events from the bus
pub fn handleEvent(ctx: *anyopaque, event: events.Event) void {
    switch (event) {
        .request_render => { ... },
        .frame_done => { ... },
        else => {},
    }
}
```

### Persistent Cairo resources for measurement

```zig
// GOOD: create once, reuse every frame
fn ensureMeasureSurface(rmod: *RenderModState) void {
    if (rmod.measure_cairo == null) {
        const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, 1, 1);
        rmod.measure_cairo = c.cairo_create(surface);
    }
}
```

**Why**: Avoids allocating and freeing a Cairo surface on every render frame.

### Arena allocator owned by state struct

```zig
// GOOD: arena lives in RenderModState, initialized once
rmod.layout_arena = std.heap.ArenaAllocator.init(allocator);
// ... use on every frame ...
_ = rmod.layout_arena.reset(.retain_capacity);
// ... cleanup in app.finish() ...
rmod.layout_arena.deinit();
```

**Why**: Arena is tied to the module's lifecycle, not module-level global. `retain_capacity` avoids repeated syscalls.

### Full surface damage as default

```zig
// Current approach: damage full surface
surface.damageBuffer(0, 0, full_width, full_height);
```

This is acceptable for now. Future work may introduce incremental damage tracking.

---

## Code Review Checklist

- [ ] No module-level mutable globals
- [ ] No dead code (unused files, functions, fields)
- [ ] No duplicate implementations of the same logic
- [ ] Hot path allocations are reused (Arena, persistent Cairo surface)
- [ ] All state structs have proper `deinit()` / cleanup in `App.finish()`
- [ ] `zig build` and `make build` both pass without warnings
