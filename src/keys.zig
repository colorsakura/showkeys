const c = @import("c");

/// Type aliases for C structs, maintaining ABI compatibility.
pub const KeyList = c.struct_wsk_key_list;
pub const Keypress = c.struct_wsk_keypress;
pub const TimeSpec = c.struct_timespec;

/// Append a keypress to the linked list tail, then trim excess
/// oldest entries beyond `max_keys`.
pub fn append(keys: *KeyList, keypress: *Keypress, max_keys: c_int, now: TimeSpec) void {
    keys.last_key = now;
    keypress.next = null;

    const key_count = appendToTail(keys, keypress);
    trimOldest(keys, key_count, keyLimit(max_keys));
}

/// Free all keypresses in the list and reset it to empty.
pub fn clear(keys: *KeyList) void {
    var key = keys.head;
    while (key) |current| {
        const next = current.*.next;
        destroyKeypress(current);
        key = next;
    }
    keys.head = null;
}

/// Check whether the most recently pressed key has exceeded
/// the display timeout.
pub fn expired(keys: *const KeyList, timeout: c_int, now: TimeSpec) bool {
    if (keys.head == null) return false;

    return reachedDeadline(now, .{
        .tv_sec = keys.last_key.tv_sec + timeout,
        .tv_nsec = keys.last_key.tv_nsec,
    });
}

// ---------------------------------------------------------------------------
// C ABI bridge — called from app.zig and input.zig via `c.*`
// ---------------------------------------------------------------------------

export fn wsk_keys_append(
    keys: *KeyList,
    keypress: *Keypress,
    max_keys: c_int,
    now: *const TimeSpec,
) void {
    append(keys, keypress, max_keys, now.*);
}

export fn wsk_keys_clear(keys: *KeyList) void {
    clear(keys);
}

export fn wsk_keys_expired(
    keys: *const KeyList,
    timeout: c_int,
    now: TimeSpec,
) bool {
    return expired(keys, timeout, now);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Traverse to the tail of the linked list and append the keypress.
/// Returns the new total key count.
fn appendToTail(keys: *KeyList, keypress: *Keypress) usize {
    var link: *allowzero [*c]Keypress = &keys.head;
    var key_count: usize = 0;
    while (link.*) |key| {
        link = &key.*.next;
        key_count += 1;
    }

    link.* = keypress;
    return key_count + 1;
}

/// Remove oldest entries from the head until the count is within `max_keys`.
fn trimOldest(keys: *KeyList, key_count_initial: usize, max_keys: usize) void {
    var key_count = key_count_initial;
    while (key_count > max_keys) {
        const oldest = keys.head orelse break;
        keys.head = oldest.*.next;
        destroyKeypress(oldest);
        key_count -= 1;
    }
}

/// Convert a potentially-negative C max_keys value to a safe usize limit.
fn keyLimit(max_keys: c_int) usize {
    return if (max_keys <= 0) 0 else @intCast(max_keys);
}

/// Compare two timestamps, returning true if `now` has passed `deadline`.
fn reachedDeadline(now: TimeSpec, deadline: TimeSpec) bool {
    if (now.tv_sec > deadline.tv_sec) return true;
    if (now.tv_sec < deadline.tv_sec) return false;
    return now.tv_nsec >= deadline.tv_nsec;
}

/// Free a C-allocated keypress struct.
fn destroyKeypress(keypress: [*c]Keypress) void {
    c.free(keypress);
}
