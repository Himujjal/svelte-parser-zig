const std = @import("std");

const Allocator = std.mem.Allocator;

// pub const Chars = enum {
//     _S = 32, // ' '
//     _N = 10, // \n
//     _T = 9, // \t
//     _R = 13, // \r
//     _F = 12, // \f
//     Lt = 60, // <
//     Ep = 33, // !
//     Cl = 45, // -
//     Sl = 47, // /
//     Gt = 62, // >
//     Qm = 63, // ?
//     La = 97, // a
//     Lz = 122, // z
//     Ua = 65, // A
//     Uz = 90, // Z
//     Eq = 61, // =
//     Sq = 39, // '
//     Dq = 34, // "
//     Ld = 100, // d
//     Ud = 68, //D
// };

/// Basically an enum of all Possible Token Types
/// Referred from https://github.com/antlr/grammars-v4/blob/master/javascript/typescript/TypeScriptLexer.g4
pub const TokenType = enum {
    Literal,
    OpenTag, // trim leading '<'
    OpenTagEnd, // trim tailing '>', only could be '/' or ''
    CloseTag, // trim leading '</' and tailing '>'
    Whitespace, // the whitespace between attributes
    AttrValueEq,
    AttrValueNq,
    AttrValueSq,
    AttrValueDq,

    IFStart,
    IFEnd,
    Else,
    ElseIf,

    EachStart,
    EachEnd,

    KeyStart,
    KeyEnd,

    AsyncStart,
    AsyncThen,
    AsyncCatch,
    AsyncEnd,

    AtHtml,
    AtConst,
    AtDebug,

    SvelteVarStart,
    SvelteVarRawText,
    SvelteVarEnd,

    EOF,
};

pub const Token = struct {
    const Self = @This();

    tok_type: TokenType = TokenType.EOF,

    /// Index of the start of the token in the array
    start: usize = 0,

    /// end of the token in the string stream
    end: usize = 0,

    pub fn getTokenStr(self: *const Self, code: []const u8) []const u8 {
        return code[self.start..self.end];
    }

    pub fn toString(
        self: *const @This(),
        allocator: Allocator,
        code: []const u8,
    ) []const u8 {
        var res: []const u8 = std.fmt.allocPrint(
            allocator,
            "[\"{s}\", {s}, {d}, {d}]",
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

pub fn getTokenTypeFromString(string: []const u8) TokenType {
    if (std.mem.eql(u8, string, "#if")) return TokenType.IFStart; // 'break';
    if (std.mem.eql(u8, string, "/if")) return TokenType.IFEnd; // 'break';
    if (std.mem.eql(u8, string, ":else")) return TokenType.Else; // 'break';

    if (std.mem.eql(u8, string, "#key")) return TokenType.KeyStart;
    if (std.mem.eql(u8, string, "/key")) return TokenType.KeyEnd;

    if (std.mem.eql(u8, string, "#async")) return TokenType.AsyncStart;
    if (std.mem.eql(u8, string, ":catch")) return TokenType.AsyncCatch;
    if (std.mem.eql(u8, string, ":then")) return TokenType.AsyncThen;
    if (std.mem.eql(u8, string, "/async")) return TokenType.AsyncEnd;

    if (std.mem.eql(u8, string, "#each")) return TokenType.EachStart;
    if (std.mem.eql(u8, string, "/each")) return TokenType.EachEnd; // {#each}

    if (std.mem.eql(u8, string, "@html")) return TokenType.AtHtml; // {@html}
    if (std.mem.eql(u8, string, "@const")) return TokenType.AtConst; // {@const}
    if (std.mem.eql(u8, string, "@debug")) return TokenType.AtDebug; // {@debug };

    return TokenType.Literal;
}
