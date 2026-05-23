# 优化渲染流程和重构渲染代码

## Goal

重构 showkeys 的渲染管线，消除冗余/死代码，优化每帧性能，使渲染架构清晰、可维护、高性能。

## 我已了解的现状

通过源码分析，我发现了以下问题：

### 🗑️ 死代码
- **`render.zig` 是废弃的旧版渲染路径**：未被任何文件 import，其中 `frameListener` 读的 `wayland.dirty` 在新代码中从未被设为 `true`
- **`types.Wayland.dirty` 字段**：仅在死代码 `render.zig` 中被读取，已无意义
- **`types.Wayland.frame_callback` / `frame_scheduled`**：`render_mod.zig` 使用自己的 `RenderModState.frame_callback` / `frame_scheduled`，`Wayland` 中的同名字段是遗留冗余

### 🔄 重复代码
- **`setupFontOptions()` / `toCairoSubpixelOrder()`** 在 `render.zig` 和 `render_mod.zig` 中各有一份完全相同的实现
- **`renderFrame()` 核心逻辑** 在两个文件中几乎完全一样

### ⚡ 性能问题
1. **每帧分配临时 Cairo surface**：`cairo_image_surface_create(ARGB32, 1, 1)` 每帧创建再销毁，仅用于测量文本。可复用
2. **每帧完整重算 layout**：`measureKeycaps()` 遍历整个 key list、调用 Pango 测量、分配 layout 数组。如果 key list 不变（例如 idle 时），结果相同
3. **全局 Arena 未清理**：`keycap.layout_arena` 是模块级全局变量，`initialized` 标志后从未调用 `.deinit()`
4. **全表面 damage**：`damageBuffer(0, 0, full, full)`，可以收窄为仅变化区域
5. **每帧重新计算 anchor 偏移**：`renderKeycaps()` 内对每个 layout 的目标 x 位置计算在每帧都重复

### 🏗️ 架构问题
1. **`keycap.zig` 的全局 `layout_arena`**：不归 App 拥有，不 Arena-idiomatic，应该作为参数传入或放到 App/RenderModState
2. **`renderKeycaps()` 修改 layout.x 后恢复**：`layout.x = draw_x; ... layout.x = layout_x_saved` 这种 hack 说明设计上有瑕疵
3. **`keycap.zig` 的 `shift_active` 全局变量**：应该放在 RenderModState 或通过返回值传递

### 🧪 未使用的公共 API
- `keycap.renderKeycapsToCairo()` 是一个包装函数，可能未被使用

## Assumptions (temporary)

- `render_mod.zig` 是当前活跃的渲染路径，`render.zig` 可以删除
- App 只通过事件总线触发渲染，rest 都是安全的清理目标
- 性能瓶颈主要在小屏幕和高频率按键时，优化目标是减少不必要的分配和计算

## Open Questions

1. 是否需要保留 `render.zig` 作为回退路径？（强烈建议删除）
2. 优化范围：只做架构清理 + 低 hanging fruit 性能优化，还是深入做增量渲染？
3. temp Cairo surface 复用：是否值得引入测量专用 Cairo surface？

## Requirements (evolving)

- [ ] 删除废弃的 `render.zig` 和 `types.Wayland` 中对应的死字段
- [ ] 消除重复的 `setupFontOptions()` / `toCairoSubpixelOrder()`
- [ ] 避免每帧分配临时 Cairo surface
- [ ] 全局 `layout_arena` → 移到 App 或 RenderModState
- [ ] 全局 `shift_active` → 移到 RenderModState
- [ ] 消除 `layout.x` 保存/恢复 hack

## Acceptance Criteria (evolving)

- [ ] `zig build` 编译通过，无警告
- [ ] 视觉效果与重构前一致
- [ ] 性能有可测量的改进（perf 工具或肉眼观察）
- [ ] 所有模块职责清晰，无重复代码

## Definition of Done

- 删除死代码 / 消除重复
- 重构后 `zig build` / `make build` 编译通过
- 视觉效果不变
- 架构清理彻底（无遗留 dead fields / dead wrappers）

## Out of Scope (explicit)

- 不改变事件总线架构
- 不更改 Wayland protocol 交互
- 不添加新功能（如多 Output 渲染、GPU 加速等）

## Technical Notes

### Key Files
| File | 用途 |
|---|---|
| `src/render.zig` | 🗑️ 死代码（旧版渲染路径），可删除 |
| `src/render_mod.zig` | ✅ 当前活跃的渲染模块（事件总线驱动） |
| `src/keycap.zig` | Keycap 测量 + 渲染（需要重构） |
| `src/types.zig` | 数据结构（含死字段） |
| `src/app.zig` | 应用初始化 + 事件循环（调用渲染） |
| `src/shm.zig` | SHM 缓冲区管理 |
| `src/wayland.zig` | Wayland surface 生命周期 |
| `src/wayland_mod.zig` | Wayland 模块（事件总线驱动） |

### render_mod.zig 与 render.zig 的对比

**render_mod.zig** (新/活跃):
- 通过事件总线接收 `.request_render` 和 `.frame_done`
- frame callback 通过 `RenderModState` 管理
- 调用 `keycap.measureKeycaps()` + `keycap.renderKeycaps()`

**render.zig** (旧/死):
- 有独立的 `frameListener` 直接在主线程回调
- 使用 `wayland.dirty` 标志（从未被设置）
- 未在任何文件被 import

### 数据流
```
Input Event → appendKeypressToApp() → requestRender()
  → EventBus(.request_render) → render_mod.handleEvent
  → renderFrame() → measureKeycaps() → getNextBuffer() → renderKeycaps() → commit
  → Frame done → EventBus(.frame_done) → 如果 pending，再渲染
```

## Research References

(无需外部研究，已通过代码库分析完成)
