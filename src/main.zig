const builtin = @import("builtin");
const std = @import("std");

const os = @import("os.zig");
const HttpClient = @import("HttpClient.zig");
const SourceRegistry = @import("SourceRegistry.zig");
const State = @import("State.zig");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
    };

    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var registry: SourceRegistry = try .load(gpa);
    defer registry.deinit(gpa);

    var state: State = try .load(gpa, registry);
    defer state.deinit(gpa);

    var now: i64 = 0;

    if (registry.sources.count() == 0) {
        os.notify(.{ .title = "Hoot!", .body = "No sources configured, nothing to keep an eye on..", .url = null });
    } else {
        os.notify(.{ .title = "Hoot!", .body = "I'm watchin", .url = null });
    }

    var client: HttpClient = .init(gpa);
    defer client.deinit();

    while (true) {
        now = std.time.timestamp();
        if (state.sources.items.len > 0 and state.sources.items[0].next_run < now) {
            const notifications = registry.check(gpa, now, &client, &state.sources.items[0]);
            var i = notifications.len;
            while (i > 0) : (i -= 1) {
                const n = notifications[i - 1];
                os.notify(n);
                n.deinit(gpa);
            }
            gpa.free(notifications);

            state.sort();
            try state.save(gpa);
        }

        for (0..10) |_| {
            os.handleEvents();
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }
}
