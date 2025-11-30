const std = @import("std");

const Atom = @import("./sources/Atom.zig");
const Rss = @import("./sources/Rss.zig");
const GitHubMerge = @import("./sources/GitHubMerge.zig");
const SourceState = @import("State.zig").Source;
const os = @import("os.zig");
const HttpClient = @import("HttpClient.zig");
const Config = @import("Config.zig");
const time = @import("time.zig");

const log = std.log.scoped(.lynceus);

const Registry = @This();

const SourceCtx = union(enum) {
    atom: Atom,
    rss: Rss,
    gitHubMerge: GitHubMerge,
};

const Source = struct {
    title: ?[]const u8,
    ctx: SourceCtx,

    pub fn deinit(self: Source, gpa: std.mem.Allocator) void {
        switch (self.ctx) {
            inline else => |c| c.deinit(gpa),
        }
    }
};

arena: *std.heap.ArenaAllocator,
sources: std.AutoHashMapUnmanaged(u64, Source),

pub fn load(gpa: std.mem.Allocator) !Registry {
    const file = try configFile(gpa);
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var reader = file.reader(&buffer);

    var jr: std.json.Reader = .init(gpa, &reader.interface);
    defer jr.deinit();

    var registry: Registry = .{
        .arena = try gpa.create(std.heap.ArenaAllocator),
        .sources = .empty,
    };
    errdefer gpa.destroy(registry.arena);

    registry.arena.* = std.heap.ArenaAllocator.init(gpa);
    errdefer registry.arena.deinit();

    const cfg = try std.json.parseFromTokenSourceLeaky(Config, registry.arena.allocator(), &jr, .{ .ignore_unknown_fields = true });
    try registry.sources.ensureTotalCapacity(gpa, @intCast(cfg.sources.len));

    for (cfg.sources) |s| registry.sources.putAssumeCapacity(s.hash(), switch (s.spec) {
        inline else => |spec, tag| .{
            .title = s.title,
            .ctx = @unionInit(SourceCtx, @tagName(tag), .{ .spec = spec }),
        },
    });

    return registry;
}

pub fn check(
    self: Registry,
    gpa: std.mem.Allocator,
    now: i64,
    client: *HttpClient,
    state: *SourceState,
) []os.Notification {
    log.debug("running {d} at {s}", .{ state.config_hash, time.formatISO(now) });
    var source = self.sources.getPtr(state.config_hash) orelse unreachable;

    state.next_run = now + 3600;
    switch (source.ctx) {
        inline else => |*ctx| return ctx.check(gpa, client, state, source.title),
    }
}

pub fn deinit(self: *Registry, gpa: std.mem.Allocator) void {
    var it = self.sources.valueIterator();
    while (it.next()) |c| c.deinit(gpa);
    self.sources.deinit(gpa);
    self.arena.deinit();
    gpa.destroy(self.arena);
}

fn configFile(gpa: std.mem.Allocator) !std.fs.File {
    const config = try std.process.getEnvVarOwned(gpa, "XDG_CONFIG_HOME");
    defer gpa.free(config);

    const path = try std.fs.path.join(gpa, &.{ config, "lynceus", "config.json" });
    defer gpa.free(path);

    return std.fs.openFileAbsolute(path, .{ .mode = .read_only });
}
