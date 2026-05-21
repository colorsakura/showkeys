# AGENTS.md

## Project overview

ShowKeys is a C11 Wayland utility that displays recent keyboard and pointer button presses on screen. It targets Wayland compositors with `wlr_layer_shell_v1` support and reads input through libinput, requiring setuid/root privileges only during startup to open input devices.

## Common commands

### Build

```sh
# Preferred development build
zig build

# Release-style build used by Makefile
make build
# equivalent: zig build --release=fast

# Optional: restrict the compiled input-device prefix
zig build -Ddevpath=/dev/input/
```

### Install / uninstall

```sh
# Installs zig-out/bin/showkeys and marks it setuid so it can read input events
sudo make install

# Installs bundled themes to /usr/share/showkeys/
sudo make theme

sudo make uninstall
```

## High-level architecture

- `src/main.c` only drives the lifecycle: privileged setup, normal initialization, event loop, cleanup.
- `src/app.c` owns the central `struct wsk_app` state from `include/app.h`. It initializes configuration, theme, libinput, and Wayland, then polls both libinput and Wayland file descriptors in one loop.
- `src/devmgr.c` is the privileged helper. At startup it forks a root child that opens evdev paths under compiled `INPUTDEVPATH`, sends file descriptors over a Unix socket, and the parent immediately drops privileges.
- `src/input.c` connects libinput/udev with the privileged devmgr open callback. It receives the Wayland keymap via `src/wayland.c`, uses xkbcommon to translate keycodes, and appends keyboard or pointer-button presses to `struct wsk_key_list`.
- `src/keys.c` maintains the linked list of visible keypresses, including max-key trimming and timeout expiration.
- `src/wayland.c` owns registry binding, output tracking, seat/keyboard listeners, layer-shell surface creation, dirty-state scheduling, and frame callbacks. Rendering is frame-paced via `wl_surface_frame` and only happens once the layer surface is configured.
- `src/render.c` performs the two-phase frame path: measure keycap layout with a temporary Cairo context, resize/reconfigure the layer surface if needed, then draw directly into the next SHM buffer.
- `src/shm.c` implements the double-buffered Wayland SHM pool buffers used by rendering.
- `src/keycap.c`, `src/pango.c`, `src/color.c`, `src/theme.c`, and `src/icons.c` implement visual layout and drawing: Pango text measurement/rendering, color parsing, SVG key backgrounds, and cached special-key icons.
- `themes/default/key.svg` and `themes/default/icons/*.svg` are the bundled SVG theme assets. `-k path/to/key.svg` makes icons resolve from an `icons/` directory beside that key SVG.
- `protocols/` contains the vendored layer-shell XML. The `build.zig` generates Wayland protocol bindings via `zig-wayland`.

## Design rules

- 遵循 Apple Design 设计语言：简洁、克制、圆润、轻量，优先使用清晰的层次、柔和的高光和低对比阴影。
- 默认主题采用 glassmorphism / Apple 风格玻璃质感：半透明渐变、细边框、高光层和轻微底部阴影，避免厚重拟物或高饱和装饰。
- SVG 图标统一为 24x24：使用 `viewBox="0 0 24 24"`，并显式声明 `width="24" height="24"`。
- 图标以线性符号为主：主线条使用 `#f5f5f7`，`fill="none"`，`stroke-linecap="round"`，`stroke-linejoin="round"`。
- 图标线宽保持一致：常规图标主 stroke 约 `1.9`，强调元素可略粗，辅助元素使用较低透明度（如 `opacity="0.55"` 或 `0.38`）。
- 同一组图标应保持统一的视觉重量、留白、圆角和居中构图；不要混用明显不同的图标风格。
- keycap 背景 SVG 应与图标配套：圆角玻璃面板、柔和高光、细 rim 边框，保证文字和特殊键图标在深色/半透明背景上有足够可读性。
