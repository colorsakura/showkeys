# ShowKeys

[![Wiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/colorsakura/showkeys)

Displays keypresses on screen on supported Wayland compositors (requires
`wlr_layer_shell_v1` support).

## Installation

Dependencies:

- cairo
- libinput
- librsvg
- pango
- udev 
- wayland 
- xkbcommon

```shell
# build
make build

# install
make install
```

showkeys must be configured as setuid during installation. It requires root
permissions to read input events. These permissions are dropped after startup.

## Usage

```
showkeys [-b|-f|-s #RRGGBB[AA]] [-F font] [-t timeout] [-n max-keys]
    [-a top|left|right|bottom] [-m margin] [-o output] [-k key.svg]
```

- *-b #RRGGBB[AA]*: set background color
- *-f #RRGGBB[AA]*: set foreground color
- *-s #RRGGBB[AA]*: set color for special keys
- *-F font*: set font (Pango format, e.g. 'monospace 24')
- *-t timeout*: set timeout before clearing old keystrokes
- *-n max-keys*: set the maximum number of keycaps to show at once (default: 5)
- *-a top-right|top-center|top-left|bottom-right|bottom-center|bottom-left|center-right|center-left|center*: anchor the keystrokes (default: bottom-right)
- *-m margin*: set a margin (in pixels) from the nearest edge
- *-o output*: request showkeys is shown on the specified output
  (unimplemented)
- *-k key.svg*: draw each keycap background with an SVG file. If loading or
  rendering fails, showkeys falls back to the built-in Cairo keycap background.
  Special-key icons are loaded from an `icons/` directory next to `key.svg`
  when available, for example `icons/enter.svg`, `icons/backspace.svg`,
  `icons/escape.svg`, `icons/tab.svg`, `icons/delete.svg`, `icons/home.svg`,
  `icons/page-up.svg`, `icons/caps-lock.svg`, `icons/shift.svg`,
  `icons/ctrl.svg`, `icons/super.svg`, `icons/arrow-left.svg`,
  `icons/volume-up.svg`, and `icons/brightness.svg`.

## Roadmap

- [ ] 新增配置文件，优先级：系统配置->用户配置->命令行
  - [ ] 配置文件
  - [ ] 系统级，用户级
  - [ ] 优先级
- [ ] 隐私模式：
  - [ ] 检测密码输入事件(当前无法实现)；
  - [ ] 私密字符匹配
- [ ] 监控配置的变动，自动应用
- [ ] 使用 GPUI 编写一个配置界面，与主程序隔离
- [ ] 主题格式确定