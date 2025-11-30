const std = @import("std");

const Atom = @import("./sources/Atom.zig");
const Rss = @import("./sources/Rss.zig");
const GitHubMerge = @import("./sources/GitHubMerge.zig");

const Config = @This();

const Source = struct {
    title: ?[]const u8,
    spec: union(enum) {
        atom: Atom.Spec,
        rss: Rss.Spec,
        gitHubMerge: GitHubMerge.Spec,
    },

    pub fn hash(self: Source) u64 {
        var h: std.hash.Fnv1a_64 = .init();
        h.update(@tagName(self.spec));
        switch (self.spec) {
            inline else => |s| s.updateHash(&h),
        }

        return h.final();
    }
};

sources: []Source,
