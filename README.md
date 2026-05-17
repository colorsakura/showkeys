# ShowKeys

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

```
$ meson build
$ ninja -C build
# ninja -C build install
# chmod a+s /usr/bin/showkeys
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
- *-a top|left|right|bottom*: anchor the keystrokes to an edge. May be specified
  twice.
- *-m margin*: set a margin (in pixels) from the nearest edge
- *-o output*: request showkeys is shown on the specified output
  (unimplemented)
- *-k key.svg*: draw each keycap background with an SVG file. If loading or
  rendering fails, showkeys falls back to the built-in Cairo keycap background.
  Special-key icons are loaded from an `icons/` directory next to `key.svg`
  when available, for example `icons/enter.svg`, `icons/backspace.svg`,
  `icons/space.svg`, `icons/shift.svg`, `icons/ctrl.svg`, `icons/alt.svg`,
  `icons/super.svg`, and `icons/arrow-left.svg`.
