const std = @import("std");

const parser = @import("./parser.zig");

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Error = parser.Error;

pub const TokenType = enum {
    EOF,
};

pub const Token = struct {
    const Self = @This();

    tok_type: TokenType = TokenType.EOF,

    /// Index of the start of the token in the array
    start: usize = 0,

    /// end of the token in the string stream
    end: usize = 0,

    pub fn toString(
        self: *const @This(),
        allocator: Allocator,
        code: []const u8,
    ) []const u8 {
        var res: []const u8 = std.fmt.allocPrint(
            allocator,
            "({s},{s},{d},{d})",
            .{
                code[self.start..self.end],
                self.tok_type,
                self.start,
                self.end,
            },
        ) catch "-----------";
        return res;
    }

    pub fn testing(self: *Self, allocator: Allocator) void {
        var res: []const u8 = std.fmt.allocPrint(
            allocator,
            "({d},{d})",
            .{ self.start, self.end },
        ) catch "-----------";
        return res;
    }
};

pub const Scanner = struct {
    const Self = @This();

    allocator: Allocator,
    code: []const u8 = undefined,

    tokens: *ArrayList(Token),
    errors: *ArrayList(Error),
    warnings: *ArrayList(Error),

    scanner_arena: *ArenaAllocator,
    internal_allocator: Allocator,

    pub fn init(
        allocator: Allocator,
        tokens: *ArrayList(Token),
        errors: *ArrayList(Error),
        warnings: *ArrayList(Error),
    ) Self {
        var scanner_arena = allocator.create(ArenaAllocator) catch unreachable;
        scanner_arena.* = ArenaAllocator.init(allocator);

        return Self{
            .allocator = allocator,
            .tokens = tokens,
            .errors = errors,
            .scanner_arena = scanner_arena,
            .internal_allocator = scanner_arena.allocator(),
            .warnings = warnings,
        };
    }

    pub fn scan(self: *Self, code: []const u8) *Self {
        self.code = code;
        self.tokens.append(Token{
            .tok_type = TokenType.EOF,
            .start = 0,
            .end = 5,
        }) catch unreachable;

        return self;
    }

    // Only for debugging purposes
    pub fn printTokens(self: *Self) void {
        for (self.tokens.items) |token| {
            _ = token.toString(self.internal_allocator, self.code);
        }
    }

    pub fn testScan(self: *Self) void {
        std.debug.print("\n========= TOKENS ===========\nToken length: {d}\n", .{self.tokens.items.len});
        for (self.tokens.items) |token| {
            std.debug.print("{s}\n", .{
                token.toString(self.internal_allocator, self.code),
            });
        }
        std.debug.print("====================\n", .{});
    }

    pub fn deinitInternal(self: *Self) void {
        self.scanner_arena.deinit();
        self.allocator.destroy(self.scanner_arena);
    }

    pub fn deinit(self: *Self) void {
        self.deinitInternal();
    }
};

// All the Token States
const TokenState = enum {
    Data,
    RCDATA,
    RAWTEXT,
    ScriptData,
    PLAINTEXT,
    TagOpen,
    EndTagOpen,
    TagName,
    RCDATALessThanSign,
    RCDATAEndTagOpen,
    RCDATAEndTagName,
    RAWTEXTLessThanSign,
    RAWTEXTEndTagOpen,
    RAWTEXTEndTagName,
    ScriptDataLessThanSign,
    ScriptDataEndTagOpen,
    ScriptDataEndTagName,
    ScriptDataEscapeStart,
    ScriptDataEscapeStartDash,
    ScriptDataEscaped,
    ScriptDataEscapedDash,
    ScriptDataEscapedDashDash,
    ScriptDataEscapedLessThanSign,
    ScriptDataEscapedEndTagOpen,
    ScriptDataEscapedEndTagName,
    ScriptDataDoubleEscapeStart,
    ScriptDataDoubleEscaped,
    ScriptDataDoubleEscapedDash,
    ScriptDataDoubleEscapedDashDash,
    ScriptDataDoubleEscapedLessThanSign,
    ScriptDataDoubleEscapeEnd,
    BeforeAttributeName,
    AttributeName,
    AfterAttributeName,
    BeforeAttributeValue,
    AttributeValueDoubleQuoted,
    AttributeValueSingleQuoted,
    AttributeValueUnquoted,
    AfterAttributeValueQuoted,
    SelfClosingStartTag,
    BogusComment,
    MarkupDeclarationOpen,
    CommentStart,
    CommentStartDash,
    Comment,
    CommentLessThanSign,
    CommentLessThanSignBang,
    CommentLessThanSignBangDash,
    CommentLessThanSignBangDashDash,
    CommentEndDash,
    CommentEnd,
    CommentEndBang,
    DOCTYPE,
    BeforeDOCTYPEName,
    DOCTYPEName,
    AfterDOCTYPEName,
    AfterDOCTYPEPublicKeyword,
    BeforeDOCTYPEPublicIdentifier,
    DOCTYPEPublicIdentifierDoubleQuoted,
    DOCTYPEPublicIdentifierSingleQuoted,
    AfterDOCTYPEPublicIdentifier,
    BetweenDOCTYPEPublicAndSystemIdentifiers,
    AfterDOCTYPESystemKeyword,
    BeforeDOCTYPESystemIdentifier,
    DOCTYPESystemIdentifierDoubleQuoted,
    DOCTYPESystemIdentifierSingleQuoted,
    AfterDOCTYPESystemIdentifier,
    BogusDOCTYPE,
    CDATASection,
    CDATASectionBracket,
    CDATASectionEnd,
    CharacterReference,
    NamedCharacterReference,
    AmbiguousAmpersand,
    NumericCharacterReference,
    HexadecimalCharacterReferenceStart,
    DecimalCharacterReferenceStart,
    HexadecimalCharacterReference,
    DecimalCharacterReference,
    NumericCharacterReferenceEnd,
};
