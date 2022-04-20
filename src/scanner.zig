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
    tokens: ArrayList(Token),
    code: []const u8 = undefined,

    errors: ArrayList(Error),
    warnings: ArrayList(Error),

    i_aa: *ArenaAllocator,
    i_all: Allocator,

    pub fn init(
        allocator: Allocator,
        errors: ArrayList(Error),
        warnings: ArrayList(Error),
    ) Self {
        var i_aa_wr = allocator.create(ArenaAllocator) catch unreachable;
        i_aa_wr.* = ArenaAllocator.init(allocator);

        return Self{
            .allocator = allocator,
            .tokens = ArrayList(Token).init(allocator),
            .errors = errors,
            .i_aa = i_aa_wr,
            .i_all = i_aa_wr.allocator(),
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
        std.debug.print("\n", .{});
        for (self.tokens.items) |token| {
            _ = token.toString(self.i_all, self.code);
        }
    }

    pub fn testScan(self: *Self) void {
        for (self.tokens.items) |token| {
            std.debug.print("\t{s}\t", .{
                token.toString(self.i_all, self.code),
            });
        }
    }

    pub fn deinitInternal(self: *Self) void {
        self.i_aa.deinit();
        self.allocator.destroy(self.i_aa);
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
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
