const std = @import("std");
const SourceRegistry = @import("./SourceRegistry.zig");

const State = @This();

const expected_version: u8 = 0;

pub const Source = extern struct {
    config_hash: u64,
    next_run: i64 = 0,
    last_modified: i64 = 0,

    fn sortNextRun(_: void, a: Source, b: Source) bool {
        return a.next_run < b.next_run;
    }
};

sources: std.ArrayList(Source),

pub fn load(gpa: std.mem.Allocator, registry: SourceRegistry) !State {
    const file = try stateFile(gpa);
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(&buffer);

    var state: State = .{
        .sources = try .initCapacity(gpa, registry.sources.count()),
    };

    errdefer state.sources.deinit(gpa);

    var version: [1]u8 = undefined;
    reader.interface.readSliceAll(&version) catch |e| switch (e) {
        error.EndOfStream => {},
        else => return e,
    };

    if (version[0] == expected_version) {
        while (true) {
            const item = reader.interface.takeStruct(Source, .little) catch |e| switch (e) {
                error.EndOfStream => break,
                else => return e,
            };
            if (registry.sources.contains(item.config_hash)) {
                state.sources.appendAssumeCapacity(item);
            }
        }
    }

    var it = registry.sources.keyIterator();
    while (it.next()) |k| {
        for (state.sources.items) |i| {
            if (i.config_hash == k.*) break {};
        } else state.sources.appendAssumeCapacity(.{ .config_hash = k.* });
    }

    state.sort();

    return state;
}

pub fn sort(self: State) void {
    std.mem.sort(Source, self.sources.items, {}, Source.sortNextRun);
}

pub fn save(self: State, gpa: std.mem.Allocator) !void {
    const file = try stateFile(gpa);
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);

    try writer.interface.writeByte(expected_version);
    try writer.interface.writeSliceEndian(Source, self.sources.items, .little);
    try writer.interface.flush();
}

pub fn deinit(self: *State, gpa: std.mem.Allocator) void {
    self.sources.deinit(gpa);
}

fn stateFile(gpa: std.mem.Allocator) !std.fs.File {
    const state_home = try std.process.getEnvVarOwned(gpa, "XDG_STATE_HOME");
    defer gpa.free(state_home);

    const path = try std.fs.path.join(gpa, &.{ state_home, "lynceus" });
    defer gpa.free(path);

    var dir = std.fs.openDirAbsolute(path, .{}) catch |e| switch (e) {
        error.FileNotFound => blk: {
            try std.fs.makeDirAbsolute(path);
            break :blk try std.fs.openDirAbsolute(path, .{});
        },
        else => return e,
    };
    defer dir.close();

    return dir.createFile("state", .{ .truncate = false, .read = true });
}
