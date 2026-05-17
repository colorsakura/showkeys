# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- Configure the build directory: `meson setup buildDir`
- Reconfigure after Meson option/build-file changes: `meson setup --reconfigure buildDir`
- Build: `meson compile -C buildDir`
- Alternative build command from the README: `ninja -C buildDir`
- Install: `sudo meson install -C buildDir`
- Run the built binary without installing: `./buildDir/showkeys`
- Change the input-device prefix compiled into the privileged device manager: `meson setup --reconfigure buildDir -Ddevpath=/dev/input/`
- Run tests: `meson test -C buildDir`
- Run a single Meson test, once tests exist: `meson test -C buildDir <test-name>`

There are currently no Meson test targets (`meson introspect --tests buildDir` returns `[]`). Runtime testing requires a Wayland compositor with `wlr_layer_shell_v1` support, and normal operation requires the installed binary to be setuid/root-capable so it can open input devices before dropping privileges.

## Architecture

This is a small C23 Wayland client built with Meson. The top-level `meson.build` enables warnings as errors, sets `INPUTDEVPATH` from the `devpath` Meson option, declares dependencies on Cairo, Pango/PangoCairo, libinput, libudev, Wayland, wayland-protocols, xkbcommon, and `rt`, then builds the `showkeys` executable from `src/` plus generated protocol bindings.

`protocols/meson.build` runs `wayland-scanner` for the xdg-output, xdg-shell, and vendored `wlr-layer-shell-unstable-v1.xml` protocols. The generated client headers and private protocol C files are built into the `client_protos` static library and are not checked in under `src/`.

`src/main.c` owns the application state and event loop. It starts the privileged device manager while still effectively root, drops privileges, initializes udev/libinput/xkbcommon and Wayland registry globals, creates a layer-shell surface, then polls both libinput and the Wayland display fd. Keyboard events are read through libinput, translated through xkbcommon, appended to a linked list of recent keypresses, and cleared after the configured timeout.

Rendering is split between `src/main.c`, `src/pango.c`, and `src/shm.c`. `main.c` decides when the surface is dirty and records the text drawing with Cairo, `pango.c` handles Pango layout measurement/drawing helpers, and `shm.c` manages the two-buffer Wayland shared-memory pool used for Cairo image surfaces before buffers are attached to the Wayland surface.

`src/devmgr.c` is security-sensitive. It forks a privileged child that opens evdev device paths only when they are under the compiled `INPUTDEVPATH`, passes file descriptors back to the unprivileged parent over a UNIX socket, and exits when `devmgr_finish()` sends `MSG_END`. Changes in this file affect the setuid/root portion of the program and should preserve the privilege-drop and path-prefix checks.

## 设计风格

- 遵循 Apple Design 设计语言：简洁、克制、圆润、轻量，优先使用清晰的层次、柔和的高光和低对比阴影。
- 默认主题采用 glassmorphism / Apple 风格玻璃质感：半透明渐变、细边框、高光层和轻微底部阴影，避免厚重拟物或高饱和装饰。
- SVG 图标统一为 24x24：使用 `viewBox="0 0 24 24"`，并显式声明 `width="24" height="24"`。
- 图标以线性符号为主：主线条使用 `#f5f5f7`，`fill="none"`，`stroke-linecap="round"`，`stroke-linejoin="round"`。
- 图标线宽保持一致：常规图标主 stroke 约 `1.9`，强调元素可略粗，辅助元素使用较低透明度（如 `opacity="0.55"` 或 `0.38`）。
- 同一组图标应保持统一的视觉重量、留白、圆角和居中构图；不要混用明显不同的图标风格。
- keycap 背景 SVG 应与图标配套：圆角玻璃面板、柔和高光、细 rim 边框，保证文字和特殊键图标在深色/半透明背景上有足够可读性。