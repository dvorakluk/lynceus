const std = @import("std");

const os = @import("../os.zig");
const SourceState = @import("../State.zig").Source;
const HttpClient = @import("../HttpClient.zig");

const log = std.log.scoped(.lynceus);

const GitHubMerge = @This();

pub const Spec = struct {
    owner: []const u8,
    repo: []const u8,
    branch: []const u8,
    target: union(enum) {
        pr: u64,
        sha: []const u8,
    },

    pub fn updateHash(self: Spec, h: *std.hash.Fnv1a_64) void {
        h.update(self.owner);
        h.update(self.repo);
        h.update(self.branch);
        h.update(@tagName(self.target));

        switch (self.target) {
            .sha => |t| h.update(t),
            .pr => |t| {
                const pr: [8]u8 = @bitCast(t);
                h.update(&pr);
            },
        }
    }
};

spec: Spec,
compare_ch: HttpClient.CachingHeaders = .{},
commit_ch: HttpClient.CachingHeaders = .{},
commit_sha: ?[]const u8 = null,

pub fn deinit(self: GitHubMerge, gpa: std.mem.Allocator) void {
    self.compare_ch.deinit(gpa);
    self.commit_ch.deinit(gpa);
    if (self.commit_sha) |sha| gpa.free(sha);
}

pub fn check(
    self: *GitHubMerge,
    gpa: std.mem.Allocator,
    client: *HttpClient,
    state: *SourceState,
    title_override: ?[]const u8,
) []os.Notification {
    switch (self.spec.target) {
        .sha => |sha| if (self.commit_sha == null) {
            self.commit_sha = gpa.dupe(u8, sha) catch |e| {
                log.err("duping sha: {}", .{e});
                return &.{};
            };
        },
        .pr => self.getCommitShaFromPr(gpa, client) catch |e| {
            log.err("getting commit sha from PR number: {}", .{e});
            return &.{};
        },
    }

    if (self.commit_sha == null) return &.{};

    const notifications = self.checkCommit(
        gpa,
        client,
        self.commit_sha.?,
        title_override,
    ) catch |e| {
        log.err("checking github merge: {}", .{e});
        return &.{};
    };

    // if the check was successful, stop checking this source
    if (notifications.len > 0) state.next_run = std.math.maxInt(@TypeOf(state.next_run));

    return notifications;
}

fn checkCommit(
    self: *GitHubMerge,
    gpa: std.mem.Allocator,
    client: *HttpClient,
    sha: []const u8,
    title_override: ?[]const u8,
) ![]os.Notification {
    const url = try std.fmt.allocPrint(
        gpa,
        "https://api.github.com/repos/{s}/{s}/compare/{s}...{s}",
        .{ self.spec.owner, self.spec.repo, self.spec.branch, sha },
    );

    defer gpa.free(url);

    const uri = try std.Uri.parse(url);

    var body = std.Io.Writer.Allocating.init(gpa);
    defer body.deinit();

    const status = try client.fetch(gpa, uri, &body.writer, &self.compare_ch);

    switch (status) {
        .not_modified => {
            log.debug("GH commit not modified: {f}", .{uri});
            return &.{};
        },
        .ok => {},
        else => return error.UnexpectedStatus,
    }

    const CompareRes = struct {
        status: []const u8,
        merge_base_commit: struct {
            html_url: []const u8,
        },
    };

    const compare = try std.json.parseFromSlice(
        CompareRes,
        gpa,
        body.writer.buffered(),
        .{ .ignore_unknown_fields = true },
    );
    defer compare.deinit();

    if (!std.mem.eql(u8, compare.value.status, "behind") and !std.mem.eql(u8, compare.value.status, "identical")) return &.{};

    const title: [:0]u8 = if (title_override) |to|
        try gpa.dupeZ(u8, to)
    else
        try std.fmt.allocPrintSentinel(gpa, "GH:{s}/{s}/{s} landed in {s}", .{ self.spec.owner, self.spec.repo, sha, self.spec.branch }, 0);

    var notifications: std.ArrayList(os.Notification) = try .initCapacity(gpa, 1);
    defer notifications.deinit(gpa);

    notifications.appendAssumeCapacity(.{
        .title = title,
        .body = try gpa.dupeZ(u8, " "),
        .url = try gpa.dupeZ(u8, compare.value.merge_base_commit.html_url),
    });

    return notifications.toOwnedSlice(gpa);
}

fn getCommitShaFromPr(self: *GitHubMerge, gpa: std.mem.Allocator, client: *HttpClient) !void {
    const url = try std.fmt.allocPrint(
        gpa,
        "https://api.github.com/repos/{s}/{s}/pulls/{d}",
        .{ self.spec.owner, self.spec.repo, self.spec.target.pr },
    );

    defer gpa.free(url);

    const uri = try std.Uri.parse(url);

    var body = std.Io.Writer.Allocating.init(gpa);
    defer body.deinit();

    const status = try client.fetch(gpa, uri, &body.writer, &self.commit_ch);

    switch (status) {
        .not_modified => return log.debug("GH commit not modified: {f}", .{uri}),
        .ok => {},
        else => return error.UnexpectedStatus,
    }

    const PrRes = struct { merge_commit_sha: ?[]const u8 };

    const pr = try std.json.parseFromSlice(
        PrRes,
        gpa,
        body.writer.buffered(),
        .{ .ignore_unknown_fields = true },
    );
    defer pr.deinit();

    if (pr.value.merge_commit_sha) |sha| {
        self.commit_sha = try gpa.dupe(u8, sha);
    }
}
