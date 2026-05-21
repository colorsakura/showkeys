const c = @import("c");

export fn wsk_keys_append(
    keys: *c.struct_wsk_key_list,
    keypress: *c.struct_wsk_keypress,
    max_keys: c_int,
    now: *const c.struct_timespec,
) void {
    keys.last_key = now.*;

    var link: *allowzero [*c]c.struct_wsk_keypress = &keys.head;
    var key_count: usize = 0;
    while (link.*) |key| {
        link = &key[0].next;
        key_count += 1;
    }
    link.* = keypress;
    key_count += 1;

    while (@as(c_int, @intCast(key_count)) > max_keys and keys.head != null) {
        const oldest = keys.head;
        keys.head = oldest[0].next;
        c.free(oldest);
        key_count -= 1;
    }
}

export fn wsk_keys_clear(keys: *c.struct_wsk_key_list) void {
    var key = keys.head;
    while (key) |current| {
        const next = current[0].next;
        c.free(current);
        key = next;
    }
    keys.head = null;
}

export fn wsk_keys_expired(
    keys: *const c.struct_wsk_key_list,
    timeout: c_int,
    now: c.struct_timespec,
) bool {
    if (keys.head == null) {
        return false;
    }

    const deadline_sec = keys.last_key.tv_sec + timeout;
    return now.tv_sec > deadline_sec or
        (now.tv_sec == deadline_sec and now.tv_nsec >= keys.last_key.tv_nsec);
}
