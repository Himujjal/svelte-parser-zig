const std = @import("std");
const scanner = @import("./scanner.zig");

const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const TokenType = scanner.TokenType;
const Scanner = scanner.Scanner;
const Token = scanner.Token;

pub const ParserErrorType = enum {
    MissingSemiColon,
};

pub const Error = struct {
    line: usize,
    startPosition: usize,
    endPosition: usize,
    errorMessage: []const u8,
    errorType: ParserErrorType,
};

pub const SvelteScriptLanguage = enum { JS, Dart, TypeScript };
pub const SvelteStyleLanguage = enum { CSS, SCSS, POSTCSS };

pub const ParserOptions = struct {};

pub const Tree = struct {
    const Self = @This();

    rootNode: struct {},

    pub fn toString(self: *Tree) []const u8 {
        _ = self;
        return 
        \\Div
        \\  Children
        \\      Text
        \\          Hello Svelte
        ;
    }
};

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    tree: Tree,
    scannerInstance: Scanner,

    parser_arena: *ArenaAllocator,
    internal_allocator: Allocator,

    code: []const u8 = undefined,
    errors: ArrayList(Error),
    warnings: ArrayList(Error),
    options: ParserOptions,

    pub fn init(
        allocator: Allocator,
        errors: ArrayList(Error),
        warnings: ArrayList(Error),
        options: ParserOptions,
    ) Self {
        var a = try allocator.create(ArenaAllocator);
        a.allocator()

        const scannerInstance = Scanner.init(
            allocator,
            errors,
            warnings,
        );

        return Self{
            .allocator = allocator,
            .scannerInstance = scannerInstance,
            .tree = undefined,
            .errors = errors,
            .warnings = warnings,
            .options = options,
        };
    }

    pub fn parse(self: *Self, code: []const u8) *Self {
        const s = self.scannerInstance.scan(code);

        var start = s.tokens.items[0].start;
        var end = s.tokens.items[0].end;

        std.debug.print(
            "tokens:length: {d},{d},{d},{s},{s}\n",
            .{
                s.tokens.items.len,
                s.tokens.items[0].end,
                s.tokens.items[0].start,
                code[start..end],
                code,
            },
        );
        self.scannerInstance.printTokens();
        self.scannerInstance.testScan();
        self.scannerInstance.deinitInternal();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.scannerInstance.deinit();
    }
};

test "" {
    try expect(1 == 1);
}
