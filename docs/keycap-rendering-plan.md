# 键帽式渲染与 SVG 主题设计文档

本文档描述将 showkeys 从当前“连续纯文本”渲染改造为“键帽式显示 + 可选 SVG 主题”的推荐实施顺序。目标是按阶段降低风险：先用 Cairo/Pango 建立稳定的布局模型，再逐步引入 SVG 背景、特殊键图标和主题目录。

## 背景与目标

当前渲染路径位于 `src/main.c` 的 `render_to_cairo()`：遍历 `struct wsk_keypress` 链表，普通键使用 `utf8`，特殊键使用 `name` 并追加 `+`，然后直接通过 Pango 绘制文本。该方式缺少独立键帽边界、内边距、间距和特殊键视觉层级。

改造后期望显示形态类似：

```text
[ Ctrl ] [ Alt ] [ T ]
```

核心目标：

- 每个按键独立布局与绘制。
- 支持 padding、gap、圆角背景和高度统一。
- 普通键和特殊键可使用不同样式。
- 正确处理 Wayland 输出 scale。
- 后续可用 SVG 替代 Cairo 背景。
- 后续可为特殊键添加 SVG 图标。
- 最终支持主题目录。

## 总体原则

1. **分阶段实施**：每一阶段都应可独立构建、运行，并保留上一阶段的 fallback。
2. **Pango 负责文本**：即使引入 SVG，文本仍由 Pango 绘制，避免 SVG 文本字体、hinting、国际化和 scale 问题。
3. **Cairo fallback 永远可用**：SVG 加载失败、文件缺失或主题不完整时，回退到纯 Cairo 键帽。
4. **布局与绘制分离**：先测量所有 keycap 的尺寸，再绘制背景、图标和文本。
5. **所有尺寸使用逻辑像素配置，渲染时乘以 scale**：与现有 `render_frame()` 的 recording surface 和 buffer scale 模型保持一致。

## 推荐实施顺序

### 第一阶段：纯 Cairo 键帽

先不引入 SVG，将当前纯文本渲染改为 Cairo 键帽式绘制。

示例输出：

```text
[ Ctrl ] [ Alt ] [ T ]
```

本阶段需要解决：

- padding
- 键帽间距
- 圆角背景
- 总宽度和高度计算
- 普通键/特殊键样式
- scale 适配

#### 建议数据结构

可在 `src/main.c` 内先实现小型局部结构，等功能稳定后再考虑拆分到 `src/keycap.c`：

```c
struct keycap_style {
  int padding_x;
  int padding_y;
  int gap;
  int radius;
  int border_width;
  uint32_t normal_bg;
  uint32_t normal_fg;
  uint32_t special_bg;
  uint32_t special_fg;
  uint32_t border;
};

struct keycap_layout {
  const struct wsk_keypress *key;
  const char *label;
  bool special;
  int text_width;
  int text_height;
  int text_baseline;
  int x;
  int y;
  int width;
  int height;
};
```

初始阶段可复用现有颜色选项：

- `foreground`：普通键文字色。
- `specialfg`：特殊键文字色。
- `background`：当前整面背景色，建议继续作为 surface 透明/背景清理色；如果它是透明色，则键帽背景需要新增默认值。

如果不想立即扩展 CLI，可先硬编码合理默认值：

```text
padding_x = 12
padding_y = 6
gap = 6
radius = 8
border_width = 1
normal_bg = #222222cc
special_bg = #444444cc
border = #ffffff33
```

#### 布局流程

推荐将 `render_to_cairo()` 拆成两个概念步骤：

1. 测量：遍历 `state->keys`，为每个按键计算文字尺寸和键帽尺寸。
2. 绘制：根据测量结果绘制圆角背景、边框和文本。

伪代码：

```c
width = 0;
height = 0;

for each key:
  label = key->utf8[0] ? key->utf8 : key->name;
  special = !key->utf8[0];
  get_text_size(..., label, &tw, &th, &baseline, scale);
  cap_w = tw + padding_x * 2 * scale;
  cap_h = th + padding_y * 2 * scale;
  key.x = width;
  key.width = cap_w;
  key.height = cap_h;
  width += cap_w + gap * scale;
  height = max(height, cap_h);

if keys exist:
  width -= gap * scale;

for each key:
  key.y = (height - key.height) / 2;
  draw_rounded_rect(...);
  draw text at key.x + padding_x * scale,
               key.y + padding_y * scale;
```

注意事项：

- 不再为特殊键追加 `+`。键帽之间的独立形态已经表达了组合关系。
- 文本垂直居中建议先使用 `padding_y` 简单定位；如出现视觉偏差，再基于 Pango baseline 修正。
- `render_frame()` 当前以 `width / scale`、`height / scale` 设置 layer surface，第一阶段应保持该模型。
- `wl_surface_damage_buffer()` 当前参数使用 `state->width`、`state->height`，后续可检查是否应传 buffer 像素尺寸以匹配 `damage_buffer` 语义。

#### 圆角绘制辅助函数

建议添加局部 helper：

```c
static void rounded_rectangle(cairo_t *cr, double x, double y,
                              double w, double h, double r);
```

绘制顺序：

1. `CAIRO_OPERATOR_CLEAR` 清理 surface。
2. 绘制每个键帽背景。
3. 绘制边框。
4. 绘制文字。

#### 验收标准

- 连续按键显示为独立键帽。
- 普通键和特殊键颜色不同。
- 缩放输出下键帽尺寸和文字清晰，不出现文字裁切。
- 无按键时仍销毁/隐藏 layer surface，行为与当前一致。
- 不新增 setuid/root 相关逻辑；不改动 `src/devmgr.c`。

### 第二阶段：引入 SVG 背景

增加命令行选项：

```text
-k key.svg
```

使用 SVG 替代 Cairo 键帽背景，但文本仍由 Pango 绘制。如果 SVG 加载失败，fallback 到第一阶段的 Cairo 键帽。

#### 构建依赖

建议使用 librsvg 的 Cairo 集成：

- Meson 依赖：`librsvg-2.0`
- C 头文件：`<librsvg/rsvg.h>`

Meson 中新增 dependency 后，应更新 README 的依赖列表和用法说明。

#### CLI 与状态

在 `struct wsk_state` 中增加：

```c
const char *key_svg_path;
RsvgHandle *key_svg;
bool key_svg_failed;
```

命令行：

```text
showkeys ... [-k key.svg]
```

加载时机建议在解析参数之后、进入主循环之前。也可以 lazy load，但初期直接加载更简单。

#### 渲染策略

SVG 仅作为键帽背景，不负责文本。每个键帽绘制时：

1. 如果 `key_svg` 可用，将 SVG 缩放到当前 keycap 的 `width x height`。
2. 绘制 Pango 文本。
3. 如果 SVG 渲染失败，绘制 Cairo fallback 背景，并记录 warning。

需要注意 SVG 的缩放策略：

- MVP：非等比拉伸到键帽矩形，最简单。
- 后续优化：支持 9-slice 或固定边角，避免圆角和边框被拉伸。

#### 验收标准

- `-k key.svg` 可以改变键帽背景。
- SVG 缺失、格式错误或无法渲染时，不崩溃，并回退到 Cairo 键帽。
- 文本仍然使用当前字体、前景色和 scale。

### 第三阶段：SVG 图标

为特殊键添加图标映射：

```text
Enter       -> enter.svg
BackSpace   -> backspace.svg
Shift_L     -> shift.svg
Control_L   -> ctrl.svg
Alt_L       -> alt.svg
Super_L     -> super.svg
Left        -> arrow-left.svg
Right       -> arrow-right.svg
Up          -> arrow-up.svg
Down        -> arrow-down.svg
```

#### 图标匹配规则

建议按 `key->name` 匹配，因为特殊键当前已经以 XKB keysym name 保存。

初始映射可硬编码：

```c
struct special_icon_map {
  const char *key_name;
  const char *icon_name;
};
```

注意左右修饰键：

- `Shift_L` 和 `Shift_R` 都应映射到 `shift.svg`。
- `Control_L` 和 `Control_R` 都应映射到 `ctrl.svg`。
- `Alt_L` 和 `Alt_R` 都应映射到 `alt.svg`。
- `Super_L` 和 `Super_R` 都应映射到 `super.svg`。

#### 布局策略

建议支持两种特殊键显示方式，先实现第一种：

1. **图标 + 可选文字**：图标在左，文字在右；可读性最好。
2. **仅图标**：节省空间，但用户不一定知道图标含义。

MVP 参数可先不暴露，默认特殊键有图标时显示“图标 + label”。

建议新增样式字段：

```text
icon_size = 20
icon_gap = 6
```

布局公式：

```text
content_width = icon_width + icon_gap + text_width
keycap_width = content_width + padding_x * 2
keycap_height = max(icon_height, text_height) + padding_y * 2
```

#### 图标加载

第三阶段可以先通过固定目录或相对路径加载，但更推荐直接与第四阶段主题目录一起设计。如果还没有主题目录，可临时约定图标与 `key.svg` 同目录：

```text
icons/enter.svg
icons/backspace.svg
```

#### 验收标准

- 特殊键存在图标文件时可显示图标。
- 图标缺失时仅显示文字，不影响渲染。
- 普通键不尝试加载图标。
- 多次按键不会反复从磁盘加载同一 SVG；应缓存 handle 或缓存失败状态。

### 第四阶段：主题目录

支持：

```text
showkeys --theme ~/.config/showkeys/themes/default
```

推荐目录结构：

```text
theme/
  key.svg
  special-key.svg
  icons/
    enter.svg
    backspace.svg
    shift.svg
    ctrl.svg
    alt.svg
    super.svg
    arrow-left.svg
    arrow-right.svg
    arrow-up.svg
    arrow-down.svg
```

#### 主题解析规则

建议规则：

1. `--theme DIR` 指定主题目录。
2. 普通键背景查找 `DIR/key.svg`。
3. 特殊键背景优先查找 `DIR/special-key.svg`，不存在则使用 `DIR/key.svg`，再失败则 Cairo fallback。
4. 图标查找 `DIR/icons/<icon-name>.svg`。
5. 显式传入的 `-k key.svg` 优先级高于主题中的 `key.svg`，或反过来；需要在 README 中明确。推荐：显式 CLI 参数优先。

#### 状态结构建议

```c
struct wsk_theme {
  char *dir;
  RsvgHandle *key_bg;
  RsvgHandle *special_key_bg;
  struct icon_cache *icons;
};
```

为避免在 `main.c` 中堆积逻辑，第四阶段建议拆分文件：

```text
src/theme.c
src/theme.h
```

职责：

- 解析主题路径。
- 加载背景 SVG。
- 根据 key name 返回图标 handle。
- 缓存加载失败结果。
- 释放所有资源。

#### 验收标准

- `--theme` 指定完整主题后，普通键、特殊键和图标都能从主题目录加载。
- 主题目录不完整时仍能使用 fallback。
- 显式 `-k` 与 `--theme` 的优先级行为清晰且有文档。
- README 包含主题目录结构示例。

## 建议的代码拆分

第一阶段可以只改 `src/main.c`，降低改动范围。第二阶段开始建议逐步拆分：

```text
src/keycap.c       # keycap 布局、Cairo fallback 绘制
src/keycap.h
src/theme.c        # SVG 背景、图标和主题目录
src/theme.h
src/pango.c        # 继续只负责 Pango layout 和绘制
```

长期目标是让 `src/main.c` 只负责：

- 输入事件与按键列表维护。
- Wayland surface 生命周期。
- 调用 keycap renderer 得到 width/height 并绘制。

## 命令行选项演进

建议最终用法：

```text
showkeys [-b|-f|-s #RRGGBB[AA]] [-F font] [-t timeout]
    [-a top|left|right|bottom] [-m margin] [-o output]
    [-k key.svg] [--theme DIR]
```

可选后续扩展：

```text
--key-padding-x N
--key-padding-y N
--key-gap N
--key-radius N
--icon-size N
--no-icons
```

这些样式参数不建议在第一阶段全部暴露，避免 CLI 过早膨胀。优先实现稳定默认值和主题能力。

## 测试建议

当前项目没有 Meson test target。建议以手动运行和后续单元测试结合：

### 手动测试

- 普通键：`a b c`
- 修饰键组合：`Ctrl Alt T`
- 特殊键：`Enter BackSpace Escape Tab`
- 方向键：`Left Right Up Down`
- 高 DPI/scale 输出。
- 透明背景和不透明背景。
- SVG 文件缺失、损坏、权限不可读。
- 主题目录缺少某些文件。

### 可自动化的测试点

后续若拆分 `keycap.c`，可以为纯布局函数增加单元测试：

- 单键 width/height。
- 多键 gap 计算。
- 特殊键 label/icon content width。
- scale=1 和 scale=2 的尺寸结果。
- 空按键列表返回 width=0、height=0。

## 风险与注意事项

- **scale 混用**：现有渲染以 buffer 像素绘制，再用 `wl_surface_set_buffer_scale()` 映射到逻辑像素。新增尺寸字段时必须明确是逻辑像素还是 buffer 像素。
- **SVG 依赖增加**：librsvg 会增加构建和运行依赖，应更新 Meson、README 和打包说明。
- **性能**：不要每帧从磁盘加载 SVG；背景和图标应缓存。
- **主题不完整**：必须可部分 fallback。
- **安全边界**：本功能不需要更改 privileged device manager；避免修改 `src/devmgr.c`。
- **内存释放**：新增 `RsvgHandle`、字符串路径和 icon cache 后，需要在退出路径释放。

## 里程碑总结

1. **纯 Cairo 键帽**：完成布局模型、padding/gap/圆角/普通与特殊键样式。
2. **SVG 背景**：增加 `-k key.svg`，SVG 背景失败时 fallback 到 Cairo。
3. **SVG 图标**：为特殊键添加图标映射和缓存，缺失时显示文字。
4. **主题目录**：增加 `--theme DIR`，支持背景和图标按目录加载，完善 README。
