Based on my analysis of the `colorsakura/showkeys` codebase, here are具体的 Zig 特性可用于重构的方向：

## 当前架构概览

项目已经使用了不少 Zig 特性（`comptime`、tagged unions、memory pools、`translate-c`），但仍有多个可利用 Zig 惯用法进一步改进的地方：

---

## 1. 用 `std.process.ArgIterator` 替代 C 风格的 argc/argv 解析

当前 `main.zig` 手工将 Zig 切片转为 C 风格的 `[*c][*c]u8`，再在 `config.zig` 中用 C 风格的 `i32`
索引遍历： [0-cite-0](#0-cite-0) [0-cite-1](#0-cite-1)

**重构方向**：直接使用 `std.process.ArgIterator` 或传递 `[]const [:0]const u8` 切片，避免所有 `@constCast`/`@ptrCast` 和 C
索引操作。`Config.parse` 可以接受一个 Zig 切片迭代器。

---

## 2. 用 Zig 错误联合 (`error union`) 替代布尔返回值

目前初始化函数返回 `bool` 表示成功/失败，这是 C 风格的做法： [0-cite-2](#0-cite-2) [0-cite-3](#0-cite-3)

**重构方向**：改用 `!void` 或自定义 `error` 集合，这样可以使用 `try`/`catch` 链式调用，错误信息更明确：

```zig
pub fn initPrivileged(app_ptr: *?*App) !void {
    const app = try std.heap.page_allocator.create(App);
    // ...
}
```

---

## 3. 用 Zig 的 `std.posix` 替代 C 库系统调用

`timerfd.zig` 和 `devmgr.zig` 已大量使用 `std.os.linux` 直接系统调用，但其他地方仍通过 `@import("c")` 调用
`clock_gettime`、`poll` 等： [0-cite-4](#0-cite-4)

**重构方向**：

- 用 `std.posix.poll` 替代 `c.poll`
- 用 `std.time.Instant` 或 `std.posix.clock_gettime` 替代 `c.clock_gettime`
- 这样可以减少对 translate-c 绑定的依赖

---

## 4. 用 Zig 接口模式 (comptime interface / vtable) 重构 Module 系统

当前的 `Module` 只是嵌入了一个 `event_bus` 指针： [0-cite-5](#0-cite-5)

而事件处理通过裸函数指针 + `*anyopaque` 上下文实现： [0-cite-6](#0-cite-6)

**重构方向**：使用 Zig 的 comptime 接口模式（类似 `std.mem.Allocator`），定义一个 `Module` 接口：

```zig
pub fn Module(comptime Self: type) type {
    return struct {
        pub fn handleEvent(self: *Self, event: Event) void {
            self.handleEventImpl(event);
        }
    };
}
```

或使用泛型 `EventBus`：

```zig
pub fn EventBus(comptime modules: []const type) type { ... }
```

这样可以在编译期消除虚函数调度开销并获得更好的类型安全。

---

## 5. 用 `std.ArrayList` 或带 comptime 容量的环形缓冲区替代链表

`KeyList` 是手动管理的单链表，有 `max_keys` 限制（默认 5）： [0-cite-7](#0-cite-7) [0-cite-8](#0-cite-8)

**重构方向**：使用 `std.BoundedArray(Keypress, max_keys)` 或环形缓冲区。由于 `max_keys` 是运行时配置值，可以使用
`std.ArrayList` 配合 `FixedBufferAllocator`，简化内存管理并改善缓存局部性。

---

## 6. 去掉 `extern struct`，使用纯 Zig struct

多个类型标记为 `extern struct`（保证 C ABI 布局），但项目目前几乎不导出 C
函数： [0-cite-9](#0-cite-9) [0-cite-10](#0-cite-10)

**重构方向**：将 `extern struct` 改为普通 Zig `struct`，享受编译器的字段重排优化和更好的默认对齐。只有真正需要与 C
互操作的类型（如传递给 C 库的）才保留 `extern`。

---

## 7. 使用 `std.enums` 和编译期反射简化事件分发

当前 `EventBus.publish` 是简单的线性遍历所有订阅者： [0-cite-11](#0-cite-11)

**重构方向**：利用 Zig 的 `comptime` 能力，在编译期为每种事件类型生成独立的订阅者列表，避免运行时的 tag 检查：

```zig
pub fn TypedEventBus(comptime EventEnum: type) type {
    return struct {
        // comptime-generated per-variant subscriber arrays
        subscribers: [std.meta.fields(EventEnum).len]SubscriberList = ...;
    };
}
```

---

## 8. 使用 `@embedFile` 内嵌默认主题 SVG

如果项目有默认 SVG 资源文件，可以用 `@embedFile` 将其编译进二进制，避免运行时文件查找失败：

```zig
const default_key_svg = @embedFile("themes/default/key.svg");
```

---

## 进度追踪

| 优先级 | 重构项                       | 状态 | 收益                   |
|:------:|:-----------------------------|:----:|:-----------------------|
|   高   | 错误联合替代 `bool` 返回     | ✅   | 类型安全、错误链传递   |
|   高   | Zig 参数解析替代 C argc/argv | ✅   | 消除大量 unsafe cast   |
|   中   | `std.posix` 替代 C 系统调用  | ✅   | 减少 translate-c 依赖  |
|   中   | 去掉不必要的 `extern struct` | ✅   | 性能优化、Zig 惯用法   |
|   低   | comptime 事件分发（带事件掩码）| ✅   | 消除不必要的运行时调度    |
|   低   | 环形缓冲区替代链表           | ⬜   | 缓存友好性             |
|   低   | 内嵌默认主题 SVG             | ✅   | 消除运行时文件查找失败 |
|   低   | 整个 theme/default 目录内嵌   | ✅   | 完全脱离文件系统依赖   |
|   低   | Module 系统增强             | ✅   | 编译期类型安全         |

## 已完成的改动

### 高优先级：错误联合替代 `bool` 返回

- `config.zig`: `parse()` 返回 `ParseError!void` 替代 `bool`
- `app.zig`: `initPrivileged()` 返回 `!void`，`init()` 返回 `!void`
- `input.zig`: `createUdevContext()` 返回 `InputError!*c.struct_libinput`，`assignSeat()` 返回 `InputError!void`
- `input_mod.zig`: `init()` 返回 `!void`
- `theme.zig`: `init()` 改为返回 `void`（初始化不失败）
- `wayland.zig`: `init()` 返回 `WaylandError!void`
- `main.zig`: 使用 `try`/`catch` 链式处理错误

### 高优先级：Zig 参数解析替代 C argc/argv

- `config.zig`: `parse()` 接受 `[]const [:0]const u8` 切片替代 `argc: i32, argv: [*c][*c]u8`
- `app.zig`: `init()` 接受 `[]const [:0]const u8` 切片
- `main.zig`: 直接使用 `init.minimal.args.toSlice(arena)`，消除所有 `@constCast`/`@ptrCast`

### 中优先级：`std.posix` 替代 C 系统调用

- `app.zig`: 用 `std.posix.poll` + `std.posix.pollfd` 替代 `c.poll` + `c.struct_pollfd`；用 `std.posix.POLL.IN` 替代 `c.POLLIN`

### 中优先级：去掉不必要的 `extern struct`

- `keys.zig`: `TimeSpec`、`Keypress`、`KeyList` 从 `extern struct` 改为普通 `struct`
- `app.zig`: 消除多余的 `@ptrCast(&app.keys)` 转换（同类型，不需要指针转换），直接使用 `app.keys.method()`
- `app.zig`: 移除未使用的 `KeyList` 和 `InputModule` 别名；移除未使用的 `module` import

### Module 系统增强

- `module.zig`: 引入 `ModuleBase(comptime name: enum_literal)` 泛型，给每个模块赋予编译期名字
- `input_mod.zig`/`wayland_mod.zig`: 使用 `ModuleBase(.input_mod)` / `ModuleBase(.wayland_mod)`

### 内嵌默认主题 SVG（整个 theme/default 目录）

- `src/embedded_theme.zig` — 新模块，用 comptime `@embedFile` 嵌入全部 47 个 SVG 文件（key.svg + 46 个图标）
- `src/embedded_theme/` — 内嵌的 SVG 文件副本，编译时嵌入二进制
- `theme.zig`: 当 `key_svg_path` 为 null 时，使用 `rsvg_handle_new_from_data` 从内存加载内嵌 key.svg
- `icons.zig`: `cacheGet()` 优先从内嵌数据加载 SVG（`rsvg_handle_new_from_data`），回退到文件系统
- `build.zig`: 在 C header 中添加 `rsvg_handle_new_from_data` 声明
- 删除了 `src/default_key.svg`（迁移到 `src/embedded_theme/`）

### comptime 事件分发（带事件掩码）

- `event.zig`: 用 `EventMask`（`std.EnumSet(EventTag)`）替代全量广播
  - 新增 `EventTag` = `std.meta.Tag(Event)` — 编译期事件变体枚举
  - 新增 `EventMask` = `std.EnumSet(EventTag)` — 编译期位掩码
  - `subscribeMasked()` — 新函数，注册时声明关心的事件
  - `publish()` — 只调用 mask 匹配的订阅者
  - `subscribe()` 保留向后兼容（全量 mask）
- `app.zig`: 每个模块使用精确的 `EventMask.initMany(...)` 声明关心的事件
  - `app_mod`: key_pressed, pointer_button, pointer_scroll, tick, key_expired, quit
  - `input_mod`: keymap_updated（减少 90% 的不必要调用）
  - `wayland_mod`: layer_configured, layer_closed, surface_entered_output, quit
  - `render_mod`: request_render, frame_done, layer_configured

### 涉及的文件（总计）

- `src/main.zig` — 精简入口
- `src/config.zig` — 新的 `ParseError` 错误集 + Zig 切片参数
- `src/app.zig` — 新的 `AppError` 错误集 + Zig 切片参数；`std.posix.poll` 替代 `c.poll`；消除 `@ptrCast`；精确事件 mask
- `src/input.zig` — 新的 `InputError` 错误集 + 非可选参数
- `src/input_mod.zig` — `init()` 返回 `!void`；使用 `ModuleBase(.input_mod)`
- `src/theme.zig` — `init()` 返回 `void`；`@embedFile` 内嵌默认 SVG
- `src/wayland.zig` — 新的 `WaylandError` 错误集
- `src/keys.zig` — `extern struct` → `struct`（3处）
- `src/shm.zig` — 用 `std.os.linux.clock_gettime` 替代 `c.clock_gettime`
- `src/module.zig` — 引入 `ModuleBase` 泛型
- `src/icons.zig` — `cacheGet()` 优先从内嵌数据加载
- `src/embedded_theme.zig` — 新模块，嵌入全部 SVG
- `src/embedded_theme/` — 新目录，SVG 副本（47 个文件）
- `src/event.zig` — 新增 `EventTag`、`EventMask`、`subscribeMasked()`
- `build.zig` — 添加 `rsvg_handle_new_from_data` C 声明
- `build.zig.zon` — 更新注释