const builtin = @import("builtin");
const std = @import("std");

const macos = @import("macos.zig");

pub const Notification = struct {
    title: [:0]const u8,
    body: [:0]const u8,
    url: ?[:0]const u8,

    pub fn deinit(self: Notification, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.body);
        if (self.url) |u| allocator.free(u);
    }
};

pub fn notify(n: Notification) void {
    switch (builtin.os.tag) {
        .macos => macos.dispatch_notification(n.title, n.body, n.url orelse null),
        else => unreachable,
    }
}

pub fn handleEvents() void {
    switch (builtin.os.tag) {
        .macos => macos.handle_events(),
        else => unreachable,
    }
}
