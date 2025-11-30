// This is NOT a general purpose XML parser. It was created just for lynceus feed needs.

const std = @import("std");

pub const Xml = @This();

const SourceRange = struct {
    start: u32,
    end: u32,
    fn len(self: SourceRange) u32 {
        return self.end - self.start;
    }
};

const Attribute = struct {
    key: SourceRange,
    value: SourceRange,
};

const Node = struct {
    parent_idx: u32,
    type: union(enum) {
        element: struct {
            name: SourceRange,
            attributes: []Attribute,
        },
        text: SourceRange,
    },

    fn deinit(self: Node, gpa: std.mem.Allocator) void {
        if (self.type == .element) gpa.free(self.type.element.attributes);
    }
};

pub const ElementCursor = struct {
    parsed: Xml,
    idx: u32,
    name_src: SourceRange,
    attributes: []Attribute,

    pub fn name(c: ElementCursor) []const u8 {
        return c.parsed.slice(c.name_src);
    }

    pub fn text(c: ElementCursor) []const u8 {
        for (c.parsed.nodes.items) |n| {
            if (n.parent_idx == c.idx and n.type == .text) {
                return c.parsed.slice(n.type.text);
            }
        }
        return "";
    }

    pub fn childrenIterator(c: ElementCursor) Iterator {
        return .{
            .parsed = c.parsed,
            .parent_idx = c.idx,
            .pos = c.idx + 1,
        };
    }
};

pub const Iterator = struct {
    parsed: Xml,
    parent_idx: u32,
    pos: u32,

    pub fn next(i: *Iterator) ?ElementCursor {
        while (i.pos < i.parsed.nodes.items.len) {
            const n = i.parsed.nodes.items[i.pos];
            i.pos += 1;
            if (n.parent_idx == i.parent_idx and n.type == .element) return .{
                .parsed = i.parsed,
                .idx = i.pos - 1,
                .name_src = n.type.element.name,
                .attributes = n.type.element.attributes,
            };
        }
        return null;
    }
};

content: []const u8,
nodes: std.ArrayList(Node),
pos: u32,

pub fn deinit(self: *Xml, gpa: std.mem.Allocator) void {
    for (self.nodes.items) |n| n.deinit(gpa);
    self.nodes.deinit(gpa);
}

pub fn init(content: []const u8) Xml {
    return .{
        .content = content,
        .nodes = .empty,
        .pos = 0,
    };
}

pub fn parse(self: *Xml, gpa: std.mem.Allocator) ParseError!void {
    while (true) {
        self.skipSpace();
        switch (try self.read()) {
            '<' => switch (try self.read()) {
                '!' => switch (try self.read()) {
                    '-' => try self.skipAfter("-->"),
                    '[' => try self.skipAfter("]]>"),
                    else => return ParseError.UnexpectedToken,
                },
                '?' => try self.skipAfter("?>"),
                else => {
                    self.unread();
                    return self.parseElement(gpa, 0);
                },
            },
            else => return ParseError.UnexpectedToken,
        }
    }
}

pub fn root(self: Xml) ?ElementCursor {
    if (self.nodes.items.len == 0) return null;
    const n = self.nodes.items[0];
    if (n.type != .element) return null;
    return .{
        .parsed = self,
        .idx = 0,
        .name_src = n.type.element.name,
        .attributes = n.type.element.attributes,
    };
}

pub fn slice(self: Xml, sr: SourceRange) []const u8 {
    return self.content[sr.start..sr.end];
}

const named_entities = std.StaticStringMap(u8).initComptime(.{
    .{ "lt", '<' },
    .{ "gt", '>' },
    .{ "amp", '&' },
    .{ "apos", '\'' },
    .{ "quot", '\"' },
});

pub fn decodeZ(gpa: std.mem.Allocator, in: []const u8) ![:0]const u8 {
    if (std.mem.indexOfScalar(u8, in, '&') == null) return gpa.dupeZ(u8, in);

    var out: std.ArrayList(u8) = try .initCapacity(gpa, in.len);
    errdefer out.deinit(gpa);

    var i: usize = 0;
    while (i < in.len) : (i += 1) {
        switch (in[i]) {
            '&' => {
                if (std.mem.indexOfScalarPos(u8, in, i + 2, ';')) |end| {
                    const ent = in[i + 1 .. end];
                    switch (ent[0]) {
                        '#' => {
                            const val = try if (ent[1] == 'x' or ent[1] == 'X')
                                std.fmt.parseInt(u32, ent[2..], 16)
                            else
                                std.fmt.parseInt(u32, ent[1..], 10);

                            if (31 < val and val < 256) out.appendAssumeCapacity(@intCast(val));
                        },
                        else => if (named_entities.get(ent)) |c| {
                            out.appendAssumeCapacity(c);
                        } else return error.Invalid,
                    }
                    i = end;
                }
            },
            else => |c| out.appendAssumeCapacity(c),
        }
    }

    return try out.toOwnedSliceSentinel(gpa, 0);
}

fn read(self: *Xml) !u8 {
    if (self.pos >= self.content.len) return ParseError.EndOfFile;
    defer self.pos += 1;
    return self.content[self.pos];
}

fn unread(self: *Xml) void {
    if (self.pos > 0) self.pos -= 1;
}

fn peek(self: *Xml, len: usize) ?[]const u8 {
    if (self.pos + len > self.content.len) return null;
    return self.content[self.pos .. self.pos + len];
}

fn skipSpace(self: *Xml) void {
    while (true) switch (self.read() catch return) {
        ' ', '\r', '\n', '\t' => {},
        else => return self.unread(),
    };
}

fn skipBefore(self: *Xml, c: u8) !void {
    while (true) if (c == try self.read()) return self.unread();
}

fn sourceName(self: *Xml) !SourceRange {
    const start = self.pos;
    while (true) switch (try self.read()) {
        'A'...'Z' => {},
        'a'...'z' => {},
        '0'...'9' => {},
        '_', ':', '.', '-' => {},
        else => break self.unread(),
    };
    return .{ .start = start, .end = self.pos };
}

fn sourceQuoted(self: *Xml, quote: u8) !SourceRange {
    const start = self.pos;
    while (true) {
        const c = try self.read();
        if (c == quote and self.content[self.pos - 2] != '\\') {
            return .{ .start = start, .end = self.pos - 1 };
        }
    }
}

fn skipAfter(self: *Xml, comptime str: []const u8) !void {
    if (str.len < 2) @compileError("skipAfter expects the string to be at least 2 chars long");

    while (true) {
        try self.skipBefore(str[0]);
        if (std.mem.eql(u8, str, self.peek(str.len) orelse return)) {
            self.pos += str.len;
            return;
        }
    }
}

pub const ParseError = error{
    EndOfFile,
    OutOfMemory,
    MismatchedClosingTag,
    UnexpectedToken,
};

fn parseChildren(self: *Xml, gpa: std.mem.Allocator) ParseError!void {
    const parent_idx: u32 = @intCast(self.nodes.items.len - 1);
    while (true) switch (try self.read()) {
        '<' => switch (try self.read()) {
            '/' => return,
            '!' => switch (try self.read()) {
                '-' => try self.skipAfter("-->"),
                '[' => try self.skipAfter("]]>"),
                else => return ParseError.UnexpectedToken,
            },
            '?' => return ParseError.UnexpectedToken,
            else => {
                self.unread();
                try self.parseElement(gpa, parent_idx);
            },
        },
        else => { // text node
            const start = self.pos - 1;
            var non_space: bool = false;
            while (true) switch (try self.read()) {
                ' ', '\r', '\n', '\t' => {},
                '<' => break,
                else => non_space = true,
            };

            self.unread();
            if (non_space) try self.nodes.append(gpa, .{
                .parent_idx = parent_idx,
                .type = .{ .text = .{
                    .start = start,
                    .end = self.pos,
                } },
            });
        },
    };
}

fn parseElement(self: *Xml, gpa: std.mem.Allocator, parent_idx: u32) ParseError!void {
    const name = try self.sourceName();
    var attrs: std.ArrayList(Attribute) = .empty;
    defer attrs.deinit(gpa);

    var node: Node = .{
        .parent_idx = parent_idx,
        .type = .{ .element = .{
            .name = name,
            .attributes = undefined,
        } },
    };

    while (true) {
        self.skipSpace();
        switch (try self.read()) {
            '/' => return switch (try self.read()) {
                '>' => {
                    node.type.element.attributes = try gpa.dupe(Attribute, attrs.items);
                    try self.nodes.append(gpa, node);
                },
                else => ParseError.UnexpectedToken,
            },
            '>' => {
                node.type.element.attributes = try gpa.dupe(Attribute, attrs.items);
                try self.nodes.append(gpa, node);
                break;
            },
            else => { // attributes
                self.unread();
                var attr: Attribute = .{
                    .key = try self.sourceName(),
                    .value = undefined,
                };

                self.skipSpace();
                if (try self.read() != '=') return ParseError.UnexpectedToken;
                self.skipSpace();

                const quote = try self.read();
                switch (quote) {
                    '"', '\'' => attr.value = try self.sourceQuoted(quote),
                    else => return ParseError.UnexpectedToken,
                }

                try attrs.append(gpa, attr);
            },
        }
    }

    try self.parseChildren(gpa);
    const closing_tag = self.peek(name.len()) orelse return ParseError.EndOfFile;
    if (!std.mem.eql(u8, self.slice(name), closing_tag)) return ParseError.MismatchedClosingTag;

    try self.skipBefore('>');
    self.pos += 1;
}
