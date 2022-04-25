const std = @import("std");
const scanner = @import("./scanner.zig");
const __token = @import("./token.zig");

const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;

const TokenType = __token.TokenType;
const Scanner = scanner.Scanner;
const Token = __token.Token;

pub const ParserErrorType = enum {
    MissingSemiColon,
};

pub const Error = struct {
    line: usize,
    col: usize,
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

pub const ParseError = enum {
    SurrogateInInputStream,
    NoncharacterInInputStream,
    ControlCharacterInInputStream,
    UnexpectedNullCharacter,
    UnexpectedQuestionMarkInsteadOfTagName,
    EOFBeforeTagName,
    InvalidFirstCharacterOfTagName,
    MissingEndTagName,
    EOFInTag,
    EOFInScriptHtmlCommentLikeText,
    UnexpectedEqualsSignBeforeAttributeName,
    UnexpectedCharacterInAttributeName,
    MissingAttributeValue,
    UnexpectedCharacterInUnquotedAttributeValue,
    MissingWhitespaceBetweenAttributes,
    UnexpectedSolidusInTag,
    EndTagWithAttributes,
    EndTagWithTrailingSolidus,
    CDATAInHtmlContent,
    IncorrectlyOpenedComment,
    AbruptClosingOfEmptyComment,
    EOFInComment,
    NestedComment,
    IncorrectlyClosedComment,
    EOFInDOCTYPE,
    MissingWhitespaceBeforeDOCTYPEName,
    MissingDOCTYPEName,
    InvalidCharacterSequenceAfterDOCTYPEName,
    MissingWhitespaceAfterDOCTYPEPublicKeyword,
    MissingDOCTYPEPublicIdentifier,
    MissingQuoteBeforeDOCTYPEPublicIdentifier,
    AbruptDOCTYPEPublicIdentifier,
    MissingWhitespaceBetweenDOCTYPEPublicAndSystemIdentifiers,
    MissingQuoteBeforeDOCTYPESystemIdentifier,
    MissingWhitespaceAfterDOCTYPESystemKeyword,
    MissingDOCTYPESystemIdentifier,
    AbruptDOCTYPESystemIdentifier,
    UnexpectedCharacterAfterDOCTYPESystemIdentifier,
    EOFInCDATA,
    MissingSemicolonAfterCharacterReference,
    UnknownNamedCharacterReference,
    AbsenceOfDigitsInNumericCharacterReference,
    NullCharacterReference,
    CharacterReferenceOutsideUnicodeRange,
    SurrogateCharacterReference,
    NoncharacterCharacterReference,
    ControlCharacterReference,
    DuplicateAttribute,

    NonVoidHtmlElementStartTagWithTrailingSolidus,
    TreeConstructionError,
};

pub const ErrorHandler = union(enum) {
    ignore,
    abort: ?ParseError,
    report: ArrayList(ParseError),

    pub fn sendError(self: *@This(), err: ParseError) !void {
        switch (self.*) {
            .ignore => {},
            .abort => |*the_error| {
                the_error.* = err;
                return error.AbortParsing;
            },
            .report => |*list| try list.append(err),
        }
    }

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .ignore, .abort => {},
            .report => |list| list.deinit(),
        }
    }
};

pub const Parser = struct {
    const Self = @This();

    allocator: Allocator,
    tree: Tree,
    scannerInstance: Scanner,

    code: []const u8 = undefined,
    errors: *ArrayList(Error),
    warnings: *ArrayList(Error),
    tokens: *ArrayList(Token),
    options: ParserOptions,

    parser_arena: *ArenaAllocator,
    internal_allocator: Allocator,

    pub fn init(allocator: Allocator, options: ParserOptions) Self {
        var parser_arena = allocator.create(ArenaAllocator) catch unreachable;
        parser_arena.* = ArenaAllocator.init(allocator);

        var tokens = allocator.create(ArrayList(Token)) catch unreachable;
        tokens.* = ArrayList(Token).init(allocator);
        var errors = allocator.create(ArrayList(Error)) catch unreachable;
        errors.* = ArrayList(Error).init(allocator);
        var warnings = allocator.create(ArrayList(Error)) catch unreachable;
        warnings.* = ArrayList(Error).init(allocator);

        const scannerInstance = Scanner.init(
            allocator,
            tokens,
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
            .tokens = tokens,

            .parser_arena = parser_arena,
            .internal_allocator = parser_arena.allocator(),
        };
    }

    pub fn parse(self: *Self, code: []const u8) *Self {
        const s = self.scannerInstance.scan(code);
        _ = s;
        return self;
    }

    pub fn deinitInternal(self: *Self) void {
        self.parser_arena.deinit();
        self.allocator.destroy(self.parser_arena);
        self.allocator.destroy(self.errors);
        self.allocator.destroy(self.warnings);
        self.allocator.destroy(self.tokens);
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.errors.deinit();
        self.warnings.deinit();
        self.deinitInternal();
        self.scannerInstance.deinit();
    }
};
