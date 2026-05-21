const c = @import("c");
const wayland_mod = @import("wayland");
const keys_mod = @import("keys.zig");

// ---------------------------------------------------------------------------
// Convenience aliases for wayland namespace nesting
// ---------------------------------------------------------------------------

const wl = wayland_mod.client.wl;
const zwlr = wayland_mod.client.zwlr;
const zxdg = wayland_mod.client.zxdg;

// ---------------------------------------------------------------------------
// Re-exported types from other modules
// ---------------------------------------------------------------------------

pub const Config = @import("config.zig").Config;
pub const Keypress = keys_mod.Keypress;
pub const KeyList = keys_mod.KeyList;

// ---------------------------------------------------------------------------
// Input — udev, libinput, xkbcommon state
// ---------------------------------------------------------------------------

pub const Input = struct {
    udev: ?*c.struct_udev = null,
    libinput: ?*c.struct_libinput = null,
    xkb_context: ?*c.struct_xkb_context = null,
    xkb_keymap: ?*c.struct_xkb_keymap = null,
    xkb_state: ?*c.struct_xkb_state = null,
};

// ---------------------------------------------------------------------------
// Theme — SVG keycap assets + icon cache
// ---------------------------------------------------------------------------

pub const Theme = struct {
    key_svg_path: ?[*:0]const u8 = null,
    base_dir: [*c]u8 = undefined,
    key_svg: ?*c.RsvgHandle = null,
    key_svg_failed: bool = false,
};

// ---------------------------------------------------------------------------
// PoolBuffer — double-buffered SHM buffer
// ---------------------------------------------------------------------------

pub const PoolBuffer = struct {
    buffer: ?*wl.Buffer = null,
    surface: ?*c.cairo_surface_t = null,
    cairo: ?*c.cairo_t = null,
    pango: ?*c.PangoContext = null,
    width: u32 = 0,
    height: u32 = 0,
    data: ?*anyopaque = null,
    size: usize = 0,
    busy: bool = false,
};

// ---------------------------------------------------------------------------
// Output — Wayland output tracking
// ---------------------------------------------------------------------------

pub const WskOutput = struct {
    output: ?*wl.Output = null,
    scale: i32 = 1,
    subpixel: i32 = 0,
    next: ?*WskOutput = null,
};

// ---------------------------------------------------------------------------
// Wayland — all Wayland protocol state
// ---------------------------------------------------------------------------

pub const Wayland = struct {
    display: ?*wl.Display = null,
    registry: ?*wl.Registry = null,
    compositor: ?*wl.Compositor = null,
    shm: ?*wl.Shm = null,
    seat: ?*wl.Seat = null,
    keyboard: ?*wl.Keyboard = null,
    output_mgr: ?*zxdg.OutputManagerV1 = null,
    layer_shell: ?*zwlr.LayerShellV1 = null,
    surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    width: u32 = 0,
    height: u32 = 0,
    layer_configured: bool = false,
    layer_pending_configure: bool = false,
    frame_scheduled: bool = false,
    dirty: bool = false,
    frame_callback: ?*wl.Callback = null,
    buffers: [2]PoolBuffer = .{ .{}, .{} },
    current_buffer: ?*PoolBuffer = null,
    output: ?*WskOutput = null,
    outputs: ?*WskOutput = null,
};

// ---------------------------------------------------------------------------
// App — root application state
// ---------------------------------------------------------------------------

pub const App = struct {
    devmgr: c_int = 0,
    devmgr_pid: c.pid_t = 0,
    config: Config = .{},
    input: Input = .{},
    theme: Theme = .{},
    wayland: Wayland = .{},
    keys: KeyList = .{},
    run: bool = false,
};

// ---------------------------------------------------------------------------
// KeycapLayout — per-keycap measurement / rendering coordinates
// ---------------------------------------------------------------------------

pub const KeycapLayout = struct {
    key: ?*const Keypress = null,
    label: ?[*:0]const u8 = null,
    special: bool = false,
    icon_name: ?[*:0]const u8 = null,
    icon_svg: ?*c.RsvgHandle = null,
    text_width: c_int = 0,
    text_height: c_int = 0,
    text_baseline: c_int = 0,
    x: c_int = 0,
    y: c_int = 0,
    width: c_int = 0,
    height: c_int = 0,
    icon_x: c_int = 0,
    icon_y: c_int = 0,
    text_x: c_int = 0,
    text_y: c_int = 0,
};
