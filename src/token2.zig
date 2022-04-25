const std = @import("std");
const util = @import("./util.zig");

const eqlNullSlices = util.eqlNullSlices;
const Allocator = std.mem.Allocator;

pub const TokenPosition = struct {
    start: usize,
    end: usize,

    pub fn getStringFromTokenPosition(pos: TokenPosition, code: []const u8) []const u8 {
        return code[pos.start..pos.end];
    }

    pub fn eql(lhs: TokenPosition, rhs: TokenPosition, code: []const u8) bool {
        return std.mem.eql(u8, getStringFromTokenPosition(lhs, code), getStringFromTokenPosition(rhs, code));
    }
};

pub const TokenDOCTYPE = struct {
    name: ?TokenPosition, // html, xml
    public_identifier: ?TokenPosition,
    system_identifier: ?TokenPosition,
    force_quirks: bool,
};

pub const TokenStartTag = struct {
    name: TokenPosition,
    attributes: TokenStartTag.Attributes,
    self_closing: bool,

    pub const Attributes = std.AutoArrayHashMap(TokenPosition, TokenPosition);
};

pub const TokenEndTag = struct {
    name: TokenPosition,
};

pub const TokenComment = struct {
    data: TokenPosition,
};

pub const TokenCharacter = struct {
    data: u21,
};

pub const TokenEOF = void;

pub const Token = union(enum) {
    doctype: TokenDOCTYPE,
    start_tag: TokenStartTag,
    end_tag: TokenEndTag,
    comment: TokenComment,
    character: TokenCharacter,
    eof: TokenEOF,

    pub fn deinit(self: *Token, allocator: Allocator) void {
        switch (self.*) {
            .doctype => {},
            .start_tag => |*t| {
                t.attributes.deinit(allocator);
            },
            .end_tag => {},
            .comment => {},
            .character => {},
            .eof => {},
        }
    }

    pub fn copy(self: Token, allocator: Allocator) !Token {
        switch (self) {
            .doctype => |d| {
                return Token{
                    .doctype = .{
                        .name = d.name,
                        .public_identifier = d.public_identifier,
                        .system_identifier = d.system_identifier,
                        .force_quirks = d.force_quirks,
                    },
                };
            },
            .start_tag => |st| {
                const name = st.name;
                var attributes = TokenStartTag.Attributes{};
                errdefer {
                    attributes.deinit(allocator);
                }

                var iterator = st.attributes.iterator();
                while (iterator.next()) |attr| {
                    const key = attr.key_ptr.*;
                    const value = attr.value_ptr.*;
                    try attributes.putNoClobber(allocator, key, value);
                }

                return Token{ .start_tag = .{
                    .name = name,
                    .attributes = attributes,
                    .self_closing = st.self_closing,
                } };
            },
            .end_tag => |et| {
                return Token{ .end_tag = .{ .name = et.name } };
            },
            .comment => |c| {
                return Token{ .comment = .{ .data = c.data } };
            },
            .character, .eof => return self,
        }
    }

    pub fn eql(lhs: Token, rhs: Token, code: []const u8) bool {
        if (std.meta.activeTag(lhs) != std.meta.activeTag(rhs)) return false;
        switch (lhs) {
            .doctype => return lhs.doctype.force_quirks == rhs.doctype.force_quirks and
                eqlNullSlices(lhs.doctype.name, rhs.doctype.name, code) and
                eqlNullSlices(lhs.doctype.public_identifier, rhs.doctype.public_identifier, code) and
                eqlNullSlices(lhs.doctype.system_identifier, rhs.doctype.system_identifier, code),
            .start_tag => {
                if (!(lhs.start_tag.self_closing == rhs.start_tag.self_closing)) return false;
                if (!TokenPosition.eql(lhs.start_tag.name, rhs.start_tag.name, code)) return false;
                if (lhs.start_tag.attributes.count() != rhs.start_tag.attributes.count()) return false;

                var iterator = lhs.start_tag.attributes.iterator();
                while (iterator.next()) |attr| {
                    const rhs_value = rhs.start_tag.attributes.get(attr.key_ptr.*) orelse return false;
                    const rhs_str = TokenPosition.getStringFromTokenPosition(rhs_value);
                    if (!std.mem.eql(u8, TokenPosition.eql(attr.value_ptr.*), rhs_str)) return false;
                }
                return true;
            },
            .end_tag => return eqlNullSlices(u8, lhs.end_tag.name, rhs.end_tag.name),
            .comment => return eqlNullSlices(u8, lhs.comment.data, rhs.comment.data),
            .character => return lhs.character.data == rhs.character.data,
            .eof => return true,
        }
    }

    pub fn format(tok: Token, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype, code: []const u8) !void {
        _ = fmt;
        _ = options;

        switch (tok) {
            .doctype => |d| {
                try writer.writeAll("DOCTYPE (");
                if (d.name) |name| try writer.writeAll(code[name.start..name.end]);
                if (d.public_identifier) |pi| {
                    try writer.writeAll(" PUBLIC:");
                    try writer.writeAll(code[pi.start..pi.end]);
                }
                if (d.system_identifier) |si| {
                    try writer.writeAll(" SYSTEM:");
                    try writer.writeAll(code[si.start..si.end]);
                }
                try writer.writeAll(")");
            },
            .start_tag => |t| {
                try writer.writeAll("Start tag ");
                if (t.self_closing) try writer.writeAll("(self closing) ");
                try writer.writeAll("\"");
                try writer.writeAll(code[t.name.start..t.name.end]);
                try writer.writeAll("\" [");
                var it = t.attributes.iterator();
                while (it.next()) |entry| {
                    const key = code[entry.key_ptr.*.start..entry.key_ptr.*.end];
                    const value = code[entry.value_ptr.*.start..entry.value_ptr.*.end];
                    try writer.writeAll("\"");
                    try writer.writeAll(key);
                    try writer.writeAll("\": \"");
                    try writer.writeAll(value);
                    try writer.writeAll("\", ");
                }
                try writer.writeAll("]");
            },
            .end_tag => |t| {
                try writer.writeAll("End tag \"");
                try writer.writeAll(code[t.name.start..t.name.end]);
                try writer.writeAll("\"");
            },
            .comment => |c| {
                try writer.writeAll("Comment (");
                try writer.writeAll(code[c.data.start..c.data.end]);
                try writer.writeAll(")");
            },
            .character => |c| {
                try writer.writeAll("Character (");
                switch (c.data) {
                    '\n' => try writer.writeAll("<newline>"),
                    '\t' => try writer.writeAll("<tab>"),
                    else => {
                        var code_units: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(c.data, &code_units) catch unreachable;
                        try writer.writeAll(code_units[0..len]);
                    },
                }
                try writer.writeAll(")");
            },
            .eof => {
                try writer.writeAll("End of file");
            },
        }
    }
};
