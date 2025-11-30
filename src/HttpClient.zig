const std = @import("std");

const log = std.log.scoped(.lynceus);

const HttpClient = @This();

pub const CachingHeaders = struct {
    etag: ?[]const u8 = null,

    pub fn deinit(self: CachingHeaders, gpa: std.mem.Allocator) void {
        if (self.etag) |etag| gpa.free(etag);
    }
};

client: std.http.Client,

pub fn init(gpa: std.mem.Allocator) HttpClient {
    return .{ .client = .{ .allocator = gpa } };
}

pub fn deinit(self: *HttpClient) void {
    self.client.deinit();
}

pub fn fetch(
    self: *HttpClient,
    gpa: std.mem.Allocator,
    uri: std.Uri,
    w: *std.Io.Writer,
    caching_headers: *CachingHeaders,
) !std.http.Status {
    var options: std.http.Client.RequestOptions = .{
        .keep_alive = false,
    };

    if (caching_headers.etag) |etag| {
        options.extra_headers = &.{.{ .name = "If-None-Match", .value = etag }};
    }

    var req = try std.http.Client.request(&self.client, .GET, uri, options);
    defer req.deinit();

    try req.sendBodiless();

    const redirect_buffer: []u8 = try self.client.allocator.alloc(u8, 8 * 1024);
    defer self.client.allocator.free(redirect_buffer);

    var res = try req.receiveHead(redirect_buffer);

    if (res.head.status != .ok) return res.head.status;

    var header_it = res.head.iterateHeaders();
    while (header_it.next()) |h| if (std.ascii.eqlIgnoreCase(h.name, "ETag")) {
        if (caching_headers.etag) |etag| gpa.free(etag);
        caching_headers.etag = try gpa.dupe(u8, h.value);
        break;
    };

    const decompress_buffer: []u8 = switch (res.head.content_encoding) {
        .identity => &.{},
        .zstd => try self.client.allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try self.client.allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer self.client.allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = res.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

    _ = reader.streamRemaining(w) catch |err| switch (err) {
        error.ReadFailed => return res.bodyErr().?,
        else => |e| return e,
    };

    return .ok;
}
