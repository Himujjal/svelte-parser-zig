const std = @import("std");
const expect = std.testing.expect;
const parser = @import("./parser.zig");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const ParserOptions = parser.ParserOptions;
pub const Parser = parser.Parser;
pub const Error = parser.Error;
pub const ParserErrorType = parser.ParserErrorType;

pub fn parseText(allocator: Allocator, text: []const u8, options: ParserOptions) Parser {
    const errors = std.ArrayList(Error).init(allocator);
    const warnings = std.ArrayList(Error).init(allocator);

    const p = Parser.init(
        allocator,
        errors,
        warnings,
        options,
    ).parse(text);

    return p.*;
}

test "Parse Test" {
    const str: []const u8 = "<div>Hello Svelte</div>";
    var allocator = std.testing.allocator;
    var p = parseText(allocator, str, .{});
    const out = p.tree.toString();
    try expect(
        std.mem.eql(u8, out,
            \\Div
            \\  Children
            \\      Text
            \\          Hello Svelte
        ),
    );
    p.deinit();
}
