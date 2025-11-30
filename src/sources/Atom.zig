const std = @import("std");

const os = @import("../os.zig");
const time = @import("../time.zig");
const SourceState = @import("../State.zig").Source;
const HttpClient = @import("../HttpClient.zig");
const Xml = @import("encoding/Xml.zig");

const log = std.log.scoped(.lynceus);

const Atom = @This();

pub const Spec = struct {
    url: []const u8,

    pub fn updateHash(self: Spec, h: *std.hash.Fnv1a_64) void {
        h.update(self.url);
    }
};

spec: Spec,
caching_headers: HttpClient.CachingHeaders = .{},

pub fn deinit(self: Atom, gpa: std.mem.Allocator) void {
    self.caching_headers.deinit(gpa);
}

pub fn check(
    self: *Atom,
    gpa: std.mem.Allocator,
    client: *HttpClient,
    state: *SourceState,
    title_override: ?[]const u8,
) []os.Notification {
    return self.checkFallible(gpa, client, state, title_override) catch |e| {
        log.err("checking Atom: {}", .{e});
        std.debug.dumpStackTrace(@errorReturnTrace().?.*);
        return &.{};
    };
}

fn checkFallible(
    self: *Atom,
    gpa: std.mem.Allocator,
    client: *HttpClient,
    state: *SourceState,
    title_override: ?[]const u8,
) ![]os.Notification {
    const uri = try std.Uri.parse(self.spec.url);

    var body = std.Io.Writer.Allocating.init(gpa);
    defer body.deinit();

    const status = try client.fetch(gpa, uri, &body.writer, &self.caching_headers);

    switch (status) {
        .not_modified => {
            log.debug("Atom feed not modified: {f}", .{uri});
            return &.{};
        },
        .ok => {},
        else => return error.UnexpectedStatus,
    }

    var xml: Xml = .init(body.written());
    defer xml.deinit(gpa);

    try xml.parse(gpa);

    const root = xml.root() orelse return error.RootlessXml;

    var notifications: std.ArrayList(os.Notification) = .empty;
    defer notifications.deinit(gpa);
    errdefer for (notifications.items) |i| i.deinit(gpa);

    var last_modified: i64 = 0;

    var root_it = root.childrenIterator();
    while (root_it.next()) |el| {
        var feed_title: ?[]const u8 = null;
        if (std.mem.eql(u8, el.name(), "title")) {
            feed_title = el.text();
        } else if (std.mem.eql(u8, el.name(), "entry")) {
            var title: ?[]const u8 = null;
            var link: ?[]const u8 = null;
            var updated: i64 = 0;

            var property_it = el.childrenIterator();
            while (property_it.next()) |property| {
                if (std.mem.eql(u8, property.name(), "title")) {
                    title = property.text();
                } else if (std.mem.eql(u8, property.name(), "link")) {
                    for (property.attributes) |attr| {
                        if (std.mem.eql(u8, xml.slice(attr.key), "href")) link = xml.slice(attr.value);
                    }
                } else if (std.mem.eql(u8, property.name(), "updated")) {
                    updated = time.parseISO(property.text()) catch 0;
                }
            }

            if (title == null or updated == 0) {
                log.info("skipping entry for {s}", .{self.spec.url});
                continue;
            }

            if (updated <= state.last_modified) continue;
            if (updated > last_modified) last_modified = updated;

            // this is freshly configured feed, notify just one item, but keep searching for latest updated
            if (state.last_modified == 0 and notifications.items.len == 1) continue;

            try notifications.append(gpa, .{
                .title = if (title_override) |to|
                    try gpa.dupeZ(u8, to)
                else if (feed_title) |ft|
                    try Xml.decodeZ(gpa, ft)
                else
                    try gpa.dupeZ(u8, "Atom feed updated"),

                .body = try Xml.decodeZ(gpa, title.?),
                .url = if (link) |l| try gpa.dupeZ(u8, l) else null,
            });
        }
    }

    if (last_modified > 0) state.last_modified = last_modified;

    return notifications.toOwnedSlice(gpa);
}
