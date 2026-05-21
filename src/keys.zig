const std = @import("std");

/// Memory pool for keypress allocations — much faster than a general-purpose
/// allocator since every allocation is the same type.
var keypress_pool: std.heap.memory_pool.ExtraManaged(Keypress, .{}) = .init(std.heap.page_allocator);

/// Release any resources held by the key allocation module.
/// Must be called after all key lists are exhausted.
pub fn deinitModule() void {
    keypress_pool.deinit();
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Monotonic timestamp — mirrors POSIX `struct timespec` layout.
/// Use `extern` so that @sizeOf(TimeSpec) == @sizeOf(c.struct_timespec)
/// and the C ABI bridges can safely memcpy between the two.
const TimeSpec = extern struct {
    tv_sec: i64 = 0,
    tv_nsec: i64 = 0,
};

/// Per-keypress animation state.
pub const AnimState = enum(u8) {
    entering,
    visible,
    leaving,
    _,
};

/// A single keypress event with display metadata.
/// Linked-list node; all fields are public for direct field access
/// in input.zig (sym, name, utf8, anim_state, anim_start_ns).
/// `extern` guarantees in-memory layout matches the C ABI so the
/// transitional `export fn` bridges can safely pass pointers.
pub const Keypress = extern struct {
    sym: u32 = 0, // xkb_keysym_t (uint32_t on all Linux targets)
    name: [128]u8 = @splat(0), // display name (NUL-terminated)
    utf8: [128]u8 = @splat(0), // UTF-8 text (NUL-terminated)
    next: ?*Keypress = null,
    // -- animation fields --
    /// Current animation phase for this keypress.
    anim_state: AnimState = .entering,
    /// Absolute monotonic timestamp (nanoseconds) when this keypress
    /// entered its current animation phase.
    anim_start_ns: i64 = 0,
    /// Current X position of this keycap in the rendered frame
    /// (logical pixels at scale=1).  Updated every frame via
    /// interpolation toward the target layout position.
    render_x: c_int = 0,
};

/// Owning singly-linked list of keypresses with latest-event timestamp.
/// `extern` guarantees in-memory layout matches the C ABI so the
/// transitional `export fn` bridges can safely pass pointers.
pub const KeyList = extern struct {
    head: ?*Keypress = null,
    last_key: TimeSpec = .{},

    /// Allocate a zero-initialised Keypress from the pool.
    /// The caller is responsible for filling in fields and then
    /// passing ownership to `append()`.
    pub fn createKeypress() !*Keypress {
        return try keypress_pool.create();
    }

    /// Append a keypress to the tail of the list, update the timestamp,
    /// then trim the oldest entries if the count exceeds `max_keys`.
    /// Takes ownership of `keypress` (it will be freed on trim or deinit).
    pub fn append(self: *KeyList, keypress: *Keypress, max_keys: u32, now: TimeSpec) void {
        self.last_key = now;
        keypress.next = null;

        const key_count = self.appendToTail(keypress);
        self.trimOldest(key_count, if (max_keys == 0) 0 else max_keys);
    }

    /// Free all keypresses and reset the list to empty.
    pub fn clear(self: *KeyList) void {
        var key = self.head;
        while (key) |current| {
            const next = current.next;
            keypress_pool.destroy(current);
            key = next;
        }
        self.head = null;
    }

    /// Return `true` if the most recent keypress has been displayed
    /// for longer than `timeout_seconds`.
    pub fn expired(self: *const KeyList, timeout_seconds: u32, now: TimeSpec) bool {
        if (self.head == null) return false;

        const deadline = TimeSpec{
            .tv_sec = self.last_key.tv_sec + @as(i64, @intCast(timeout_seconds)),
            .tv_nsec = self.last_key.tv_nsec,
        };
        return reachedDeadline(now, deadline);
    }

    /// Returns `true` if any keypress has an animation phase still
    /// in progress (entering or shift).
    pub fn hasActiveAnimation(self: *const KeyList, anim_duration_ns: i64, now_ns: i64) bool {
        var key = self.head;
        while (key) |k| : (key = k.next) {
            if (k.anim_state != .visible) {
                const elapsed = now_ns - k.anim_start_ns;
                if (elapsed < anim_duration_ns) return true;
            }
        }
        // Check if any visible key is still shifting toward its target.
        // This is handled externally by the caller.
        return false;
    }

    /// Transition any finished entering keys to visible.
    pub fn tickAnimations(self: *KeyList, anim_duration_ns: i64, now_ns: i64) void {
        var key = self.head;
        while (key) |k| : (key = k.next) {
            if (k.anim_state != .entering) continue;
            const elapsed = now_ns - k.anim_start_ns;
            if (elapsed >= anim_duration_ns) {
                k.anim_state = .visible;
            }
        }
    }

    // -- internal helpers ---------------------------------------------

    fn appendToTail(self: *KeyList, keypress: *Keypress) usize {
        var link = &self.head;
        var key_count: usize = 0;
        while (link.*) |key| {
            link = &key.next;
            key_count += 1;
        }
        link.* = keypress;
        return key_count + 1;
    }

    fn trimOldest(self: *KeyList, key_count_initial: usize, max_keys: usize) void {
        var key_count = key_count_initial;
        while (key_count > max_keys) {
            const oldest = self.head orelse break;
            self.head = oldest.next;
            keypress_pool.destroy(oldest);
            key_count -= 1;
        }
    }
};

/// Compare two timestamps, returning true if `now` has passed `deadline`.
fn reachedDeadline(now: TimeSpec, deadline: TimeSpec) bool {
    if (now.tv_sec > deadline.tv_sec) return true;
    if (now.tv_sec < deadline.tv_sec) return false;
    return now.tv_nsec >= deadline.tv_nsec;
}
