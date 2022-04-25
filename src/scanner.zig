const std = @import("std");
const expect = std.testing.expect;

const parser = @import("./parser.zig");
const __token = @import("./token.zig");
const __util = @import("./util.zig");

const Token = __token.Token;
const TokenType = __token.TokenType;

const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Error = parser.Error;
pub const ErrorType = parser.ParserErrorType;

const State = enum {
    Literal,
    BeforeOpenTag,
    OpeningTag,
    AfterOpenTag,
    InValueNq,
    InValueSq,
    InValueDq,
    ClosingOpenTag,
    OpeningSpecial,
    OpeningDoctype,
    OpeningNormalComment,
    InNormalComment,
    InShortComment,
    ClosingNormalComment,
    ClosingTag,

    OpeningSvelteVariable,
    OpeningSvelteVariableInValueNq,
    OpeningSvelteVariableInValueDq,
};

const CodePoints = struct {
    lower: []const u8,
    upper: []const u8,
    len: usize,

    pub const doctype: CodePoints = .{ .lower = "!doctype", .upper = "!DOCTYPE", .len = 8 };
    pub const style: CodePoints = .{ .lower = "style", .upper = "STYLE", .len = 5 };
    pub const script: CodePoints = .{ .lower = "script", .upper = "SCRIPT", .len = 5 };
};

const doctype = struct { lower: "doctype", upper: "DOCTYPE", length: 7 };

pub const Scanner = struct {
    const Self = @This();

    allocator: Allocator,
    code: []const u8 = undefined,
    tokens: *ArrayList(Token),
    errors: *ArrayList(Error),
    warnings: *ArrayList(Error),
    scanner_arena: *ArenaAllocator,
    internal_allocator: Allocator,

    state: State = State.Literal,
    code_len: usize = 0,

    col: usize = 0,
    line: usize = 0,
    start: usize = 0,
    cursor: usize = 0,

    char: u8 = 0,
    in_script: bool = false,
    in_style: bool = false,
    offset: usize = 0,

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
            .warnings = warnings,
            .scanner_arena = scanner_arena,
            .internal_allocator = scanner_arena.allocator(),
        };
    }

    pub fn scan(self: *Self, code: []const u8) *Self {
        self.code = code;
        self.code_len = code.len;

        while (!self.codeEnd()) {
            self.char = self.lookAhead();

            switch (self.state) {
                .Literal => self.parseLiteral(),
                .BeforeOpenTag => self.parseBeforeOpenTag(),
                .OpeningTag => self.parseOpeningTag(),
                .AfterOpenTag => self.parseAfterOpenTag(),
                .InValueNq => self.parseInValueNq(),
                .InValueSq => self.parseInValueSq(),
                .InValueDq => self.parseInValueDq(),
                .ClosingOpenTag => self.parseClosingOpenTag(),
                .OpeningSpecial => self.parseOpeningSpecial(),
                .OpeningDoctype => self.parseOpeningDoctype(),
                .OpeningNormalComment => self.parseOpeningNormalComment(),
                .InNormalComment => self.parseNormalComment(),
                .InShortComment => self.parseShortComment(),
                .ClosingNormalComment => self.parseClosingNormalComment(),
                .ClosingTag => self.parseClosingTag(),

                .OpeningSvelteVariable => self.parseOpeningSvelteVariableGen(),
                .OpeningSvelteVariableInValueNq => self.parseOpeningSvelteVariableInValueNq(),
                .OpeningSvelteVariableInValueDq => self.parseOpeningSvelteVariableInValueDq(),
            }
            if (self.cursor < self.code.len) {
                _ = self.advance();
            }
        }
        switch (self.state) {
            .Literal,
            .BeforeOpenTag,
            .InValueNq,
            .InValueSq,
            .InValueDq,
            .ClosingOpenTag,
            .InNormalComment,
            .InShortComment,
            .ClosingNormalComment,
            .OpeningSvelteVariable,
            .OpeningSvelteVariableInValueDq,
            .OpeningSvelteVariableInValueNq,
            => self.addTokKindOnly(TokenType.Literal),
            .OpeningTag => self.addTokKindOnly(TokenType.OpenTag),
            .AfterOpenTag, .OpeningSpecial => self.addTokWithoutEnd(TokenType.OpenTag, State.InShortComment),
            .OpeningDoctype => {
                if (self.cursor - self.start == CodePoints.doctype.len) {
                    self.addTokKindOnly(TokenType.OpenTag);
                } else {
                    self.addTok(TokenType.OpenTag, State.Literal, self.start + 1);
                    self.addTokKindOnly(TokenType.Literal);
                }
            },
            .OpeningNormalComment => {
                if (self.cursor - self.start == 2) {
                    self.addTokKindOnly(TokenType.OpenTag);
                } else {
                    self.addTok(TokenType.OpenTag, State.Literal, self.start + 1);
                    self.addTokKindOnly(TokenType.Literal);
                }
            },
            .ClosingTag => {
                self.addTokKindOnly(TokenType.CloseTag);
            },
        }
        self.addTokKindOnly(TokenType.EOF);
        return self;
    }

    fn parseLiteral(self: *Self) void {
        if (self.char == '<') {
            self.addTokWithoutEnd(TokenType.Literal, State.BeforeOpenTag);
        } else if (self.char == '{' and !self.in_style and !self.in_script) {
            self.addTokWithoutEnd(TokenType.Literal, State.OpeningSvelteVariable);

            self.start = self.cursor;
            self.addTok(TokenType.SvelteVarStart, State.OpeningSvelteVariable, self.cursor + 1);
        }
    }

    fn parseBeforeOpenTag(self: *Self) void {
        const char = self.char;
        if (self.in_script or self.in_style) {
            if (self.char == '/') {
                self.state = State.ClosingTag;
                self.start = self.cursor + 1;
            } else {
                self.state = State.Literal;
            }
            return;
        }
        if ((char >= 'a' and char <= 'z') or (char >= 'A' and char <= 'Z')) {
            // <d
            self.state = State.OpeningTag;
            self.start = self.cursor;
        } else if (char == '/') {
            // </
            self.state = State.ClosingTag;
            self.start = self.cursor + 1;
        } else if (char == '<') {
            // <<
            self.addTok(TokenType.Literal, self.state, self.cursor);
        } else if (char == '!') {
            // <!
            self.state = State.OpeningSpecial;
            self.start = self.cursor;
        } else if (char == '?') {
            // <?
            // treat as short comment
            self.start = self.cursor;
            self.addTok(TokenType.OpenTag, State.InShortComment, self.cursor);
        } else {
            // <>
            // any other chars covert to normal state
            self.state = State.Literal;
        }
    }

    fn parseOpeningTag(self: *Self) void {
        const char = self.char;
        if (self.isWhiteSpace()) {
            // <div ...
            self.addTok(TokenType.OpenTag, State.AfterOpenTag, self.cursor);
        } else if (char == '>') {
            // <div>
            self.addTok(TokenType.OpenTag, self.state, self.cursor);
            self.addTok(TokenType.OpenTagEnd, self.state, self.cursor);
        } else if (self.char == '/') {
            // <div/
            self.addTok(TokenType.OpenTag, State.ClosingOpenTag, self.cursor);
        }
    }

    fn parseAfterOpenTag(self: *Self) void {
        const char = self.char;
        if (char == '>') {
            // <div >
            self.addTok(TokenType.Whitespace, self.state, self.cursor);
            self.addTok(TokenType.OpenTagEnd, self.state, self.cursor);
        } else if (char == '/') {
            // <div /
            self.addTok(TokenType.Whitespace, State.ClosingOpenTag, self.cursor);
        } else if (char == '=') {
            // <div ...=...
            self.addTok(TokenType.Whitespace, self.state, self.cursor);
            self.addTok(TokenType.AttrValueEq, self.state, self.cursor + 1);
        } else if (char == '\'') {
            // <div ...'...
            self.addTok(TokenType.Whitespace, State.InValueSq, self.cursor);
        } else if (char == '"') {
            // <div ..."...
            self.addTok(TokenType.Whitespace, State.InValueDq, self.cursor);
        } else if (char == '{') {
            // <div ..{}..
            self.start = self.cursor;
            self.addTok(TokenType.SvelteVarStart, State.OpeningSvelteVariableInValueNq, self.cursor + 1);
        } else if (!self.isWhiteSpace()) {
            // <div ...name...
            self.addTok(TokenType.Whitespace, State.InValueNq, self.cursor);
        }
    }

    fn parseInValueNq(self: *Self) void {
        const char = self.char;
        if (char == '>') {
            // <div xxx>
            self.addTokKindOnly(TokenType.AttrValueNq);
            self.addTokKindOnly(TokenType.OpenTagEnd);
        } else if (char == '/') {
            // <div xxx/
            self.addTokWithoutEnd(TokenType.AttrValueNq, State.ClosingOpenTag);
        } else if (char == '=') {
            // <div xxx=
            self.addTokKindOnly(TokenType.AttrValueNq);
            self.addTok(TokenType.AttrValueEq, State.AfterOpenTag, self.cursor + 1);
        } else if (self.isWhiteSpace()) {
            // <div xxx ...
            self.addTokWithoutEnd(TokenType.AttrValueNq, State.AfterOpenTag);
        }
    }

    fn parseInValueSq(self: *Self) void {
        if (self.char == '\'') {
            // <div 'xxx'
            self.addTok(TokenType.AttrValueSq, State.AfterOpenTag, self.cursor + 1);
        }
    }

    fn parseInValueDq(self: *Self) void {
        if (self.char == '"') {
            // <div "xxx", problem same to Sq
            self.addTok(TokenType.AttrValueDq, State.AfterOpenTag, self.cursor + 1);
        }
    }

    fn parseClosingOpenTag(self: *Self) void {
        if (self.char == '>') {
            // <div />
            self.addTokKindOnly(TokenType.OpenTagEnd);
        } else {
            // <div /...>
            self.addTokWithoutEnd(TokenType.AttrValueNq, State.AfterOpenTag);
            self.parseAfterOpenTag();
        }
    }

    fn parseOpeningSpecial(self: *Self) void {
        const char = self.char;
        switch (char) {
            // <!-
            '-' => self.state = State.OpeningNormalComment,
            // <!d
            'd', 'D' => self.state = State.OpeningDoctype,
            else => self.addTokWithoutEnd(TokenType.OpenTag, State.InShortComment),
        }
    }

    fn parseOpeningDoctype(self: *Self) void {
        self.offset = self.cursor - self.start;
        if (self.offset == CodePoints.doctype.len) {
            // <!d, <!d , start: 0, index: 2
            if (self.isWhiteSpace()) {
                self.addTokWithoutEnd(TokenType.OpenTag, State.AfterOpenTag);
            } else {
                self.unexpectedToken();
            }
        } else if (self.char == '>') {
            // <!DOCT>
            self.addTok(TokenType.OpenTag, State.Literal, self.start + 1);
            self.addTokKindOnly(TokenType.Literal);
            self.addTokKindOnly(TokenType.OpenTagEnd);
        } else if (CodePoints.doctype.lower[self.offset] != self.lookAhead() and
            CodePoints.doctype.upper[self.offset] != self.lookAhead())
        {
            // <!DOCX...
            self.addTok(TokenType.OpenTag, State.InShortComment, self.start + 1);
        }
    }

    fn parseOpeningNormalComment(self: *Self) void {
        if (self.char == '-') {
            // <!--
            self.addTok(TokenType.OpenTag, State.InNormalComment, self.cursor + 1);
        } else {
            self.addTok(TokenType.OpenTag, State.InShortComment, self.start + 1);
        }
    }

    fn parseNormalComment(self: *Self) void {
        if (self.char == '-') {
            // <!-- ... -
            self.addTokWithoutEnd(TokenType.Literal, State.ClosingNormalComment);
        }
    }

    fn parseShortComment(self: *Self) void {
        if (self.char == '>') {
            // <! ... >
            self.addTokKindOnly(TokenType.Literal);
            self.addTokKindOnly(TokenType.OpenTagEnd);
        }
    }

    fn parseClosingNormalComment(self: *Self) void {
        const offset = self.cursor - self.start;
        const char = self.char;
        if (offset == 2) {
            if (char == '>') {
                // <!-- xxx -->
                self.addTokKindOnly(TokenType.OpenTagEnd);
            } else if (char == '-') {
                // <!-- xxx ---
                self.addTok(TokenType.Literal, State.Literal, self.start + 1);
            } else {
                // <!-- xxx --x
                self.state = State.InNormalComment;
            }
        } else if (char != '-') {
            // <!-- xxx - ...
            self.state = State.InNormalComment;
        }
    }

    fn parseClosingTag(self: *Self) void {
        const offset = self.cursor - self.start;
        if (self.in_style) {
            if (self.char == '<') {
                self.start -= 2;
                self.addTokWithoutEnd(TokenType.Literal, State.BeforeOpenTag);
            } else if (self.offset < CodePoints.style.len) {
                if (CodePoints.style.lower[offset] != self.char and CodePoints.style.upper[offset] != self.char) {
                    self.start -= 2;
                    self.state = State.Literal;
                }
            } else if (self.char == '>') {
                self.addTokKindOnly(TokenType.CloseTag);
            } else if (!self.isWhiteSpace()) {
                self.start -= 2;
                self.state = State.Literal;
            }
        } else if (self.in_script) {
            if (self.char == '<') {
                self.start -= 2;
                self.addTokWithoutEnd(TokenType.Literal, State.BeforeOpenTag);
            } else if (offset < CodePoints.script.len) {
                if (CodePoints.script.lower[offset] != self.char and CodePoints.script.upper[self.offset] != self.char) {
                    self.start -= 2;
                    self.state = State.Literal;
                }
            } else if (self.char == '>') {
                self.addTokKindOnly(TokenType.CloseTag);
            } else if (!self.isWhiteSpace()) {
                self.start -= 2;
                self.state = State.Literal;
            }
        } else if (self.char == '>') {
            // </ xxx >
            self.addTokKindOnly(TokenType.CloseTag);
        }
    }

    // Parses variables that start with {}
    // if return is true, continue parsing svelte else start other parsing
    fn parseOpeningSvelteVariable(self: *Self) bool {
        while (self.isWhiteSpace() and !self.codeEnd()) {
            _ = self.advance();
        }
        self.start = self.cursor;
        var c = self.lookAhead();
        if (c == '#' or c == ':' or c == '/' or c == '@') {
            while (!self.isWhiteSpace() and !self.codeEnd() and self.lookAhead() != '}') {
                _ = self.advance();
            }
            const tok_type = __token.getTokenTypeFromString(
                self.code[self.start..self.cursor],
            );

            var temp_cursor = self.cursor;
            if (tok_type == TokenType.Else) {
                while (self.isWhiteSpace() and !self.codeEnd()) {
                    _ = self.advance();
                }
                var temp_start: usize = self.cursor;
                while (!self.isWhiteSpace() and !self.codeEnd() and self.lookAhead() != '}') {
                    _ = self.advance();
                }
                if (std.mem.eql(u8, self.code[temp_start..self.cursor], "if")) {
                    self.addTokWithoutEnd(TokenType.ElseIf, State.OpeningSvelteVariable);
                    self.start = temp_cursor;
                    self.cursor -= 1;
                    return true;
                } else {
                    self.cursor = temp_cursor;
                }
            }

            self.addTokWithoutEnd(tok_type, State.OpeningSvelteVariable);
            self.cursor -= 1;
            return true;
        } else {
            self.parseSvelteRawText();
            self.addTok(TokenType.SvelteVarRawText, State.OpeningSvelteVariable, self.cursor);
            _ = self.advance();
            return false;
        }
    }

    fn parseOpeningSvelteVariableGen(self: *Self) void {
        const b = self.parseOpeningSvelteVariable();
        if (b == false) {
            self.addTok(TokenType.SvelteVarEnd, State.Literal, self.cursor);
            self.start = self.cursor;
        }
    }

    fn parseOpeningSvelteVariableInValueNq(self: *Self) void {
        const b = self.parseOpeningSvelteVariable();
        if (b == false) {
            self.addTok(TokenType.SvelteVarEnd, State.AfterOpenTag, self.cursor);
            self.start = self.cursor;
        }
    }

    fn parseOpeningSvelteVariableInValueDq(self: *Self) void {
        const b = self.parseOpeningSvelteVariable();
        if (b == false) {
            self.addTok(TokenType.SvelteVarEnd, State.AfterOpenTag, self.cursor);
            self.start = self.cursor;
        }
    }

    fn parseSvelteRawText(self: *Self) void {
        var bracesLevel: usize = 0;
        var stringType: u8 = 0;
        var c0 = self.lookAhead();
        while (c0 != '}' or bracesLevel != 0) {
            if (c0 == '\\' and stringType != 0) {
                _ = self.advance();
                c0 = self.lookAhead();
            }

            if (c0 == '\'' or c0 == '"' or c0 == '`') {
                if (stringType == c0) {
                    stringType = 0;
                } else if (stringType == 0) {
                    stringType = c0;
                }

                _ = self.advance();
                c0 = self.lookAhead();
            } else if (c0 == '}' or c0 == '{') {
                // <div>{\"{}\"Hello { } World}</div>
                if (c0 == '{') {
                    if (stringType == 0) {
                        bracesLevel += 1;
                    }

                    _ = self.advance();
                    c0 = self.lookAhead();
                }

                if (c0 == '}') {
                    if (stringType != 0) {
                        _ = self.advance();
                        c0 = self.lookAhead();
                    } else {
                        if (bracesLevel > 0 and stringType == 0) {
                            bracesLevel -= 1;
                        }

                        _ = self.advance();
                        c0 = self.lookAhead();
                    }
                }
            } else {
                _ = self.advance();
                c0 = self.lookAhead();
            }
        }
    }

    // utility methods
    /// look one character ahead
    fn lookAhead(self: *Self) u8 {
        return if (self.cursor >= self.code.len) 0 else self.code[self.cursor];
    }

    /// look two characters ahead
    fn lookSuperAhead(self: *Self) u8 {
        if (self.cursor >= self.code.len) return 0;
        if (self.cursor + 1 >= self.code.len) return 0;
        return self.code[self.cursor + 1];
    }

    fn lookSuperDuperAhead(self: *Self) u8 {
        if (self.lookSuperAhead() != 0) {
            if (self.cursor + 2 >= self.code.len) return 0;
            return self.code[self.cursor + 2];
        }
        return 0;
    }

    fn isWhiteSpace(self: *Self) bool {
        const char = self.lookAhead();
        return (char == ' ' or
            char == '\n' or
            char == '\t' or
            char == '\r');
    }

    fn match(self: *Self, expectedChar: u8) bool {
        if (self.end()) return false;
        if (self.code[self.cursor] != expectedChar) return false;
        self.*.cursor += 1;
        return true;
    }

    fn advance(self: *Self) u8 {
        self.cursor += 1;
        self.col += 1;
        if (self.code[self.cursor - 1] == '\n') {
            self.line += 1;
            self.col = 1;
        }
        return self.code[self.cursor - 1];
    }

    fn unexpectedToken(self: *Self) void {
        self.addError("Unexpected Token");
    }

    fn addError(self: *Self, message: []const u8) void {
        self.errors.append(Error{
            .line = self.line,
            .col = self.col,
            .startPosition = self.start,
            .endPosition = self.cursor,
            .errorMessage = message,
            .errorType = ErrorType.MissingSemiColon,
        }) catch unreachable;
    }

    fn codeEnd(self: *Self) bool {
        return self.cursor >= self.code.len;
    }

    fn addTokKindOnly(self: *Self, kind: TokenType) void {
        self.addTok(kind, self.state, self.cursor);
    }

    fn addTokWithoutEnd(self: *Self, kind: TokenType, new_state: State) void {
        self.addTok(kind, new_state, self.cursor);
    }

    fn addTok(self: *Self, kind: TokenType, new_state: State, end: usize) void {
        var value = self.code[self.start..end];
        if (kind == TokenType.OpenTag or kind == TokenType.CloseTag) {
            value = __util.toLowerCase(self.internal_allocator, value);
        }
        if (kind == TokenType.OpenTag) {
            if (std.mem.eql(u8, value, "script")) {
                self.in_script = true;
            } else if (std.mem.eql(u8, value, "style")) {
                self.in_style = true;
            }
        }
        if (kind == TokenType.CloseTag) {
            self.in_script = false;
            self.in_style = false;
        }
        if (!((kind == TokenType.Literal or kind == TokenType.Whitespace) and
            end == self.start))
        {
            const tok = Token{
                .tok_type = kind,
                .start = self.start,
                .end = end,
            };
            // empty literal should be ignored
            self.tokens.append(tok) catch unreachable;
        }
        if (kind == TokenType.OpenTagEnd or kind == TokenType.CloseTag) {
            self.start = end + 1;
            self.state = State.Literal;
        } else {
            self.start = end;
            self.state = new_state;
        }
    }

    fn addToken(self: *Self, startPos: usize, endPos: usize, tok_type: TokenType) void {
        self.tokens.append(Token{
            .start = startPos,
            .end = endPos,
            .tok_type = tok_type,
        });
    }

    pub fn printTokens(self: *Self) void {
        std.debug.print("========= TOKENS ===========\nToken length: {d}\n", .{self.tokens.items.len});
        for (self.tokens.items) |tok| {
            std.debug.print("{s}\n", .{
                tok.toString(self.internal_allocator, self.code),
            });
        }
        std.debug.print("\n====================\n", .{});
    }

    pub fn deinitInternal(self: *Self) void {
        self.scanner_arena.deinit();
        self.allocator.destroy(self.scanner_arena);
    }

    pub fn deinit(self: *Self) void {
        self.deinitInternal();
    }
};

fn scannerForTestDeinit(sc: *Scanner) void {
    sc.tokens.deinit();
    sc.errors.deinit();
    sc.warnings.deinit();
    sc.allocator.destroy(sc.tokens);
    sc.allocator.destroy(sc.errors);
    sc.allocator.destroy(sc.warnings);

    sc.deinit();
}

fn getTokens(a: Allocator, code: []const u8) Scanner {
    var tokens = a.create(ArrayList(Token)) catch unreachable;
    tokens.* = ArrayList(Token).init(a);
    var errors = a.create(ArrayList(Error)) catch unreachable;
    errors.* = ArrayList(Error).init(a);
    var warnings = a.create(ArrayList(Error)) catch unreachable;
    warnings.* = ArrayList(Error).init(a);
    var scanner = Scanner.init(a, tokens, errors, warnings);

    var sc = Scanner.scan(&scanner, code);
    _ = sc;
    // sc.printTokens();

    return scanner;
}

test "Scanner Test" {
    var a = std.testing.allocator;

    var scanner = getTokens(a, "<!DOCTYPE html>");
    defer scannerForTestDeinit(&scanner);
    try expect(scanner.tokens.items.len == 5);

    var scanner2 = getTokens(a, "<!-- Hello World -->");
    defer scannerForTestDeinit(&scanner2);
    try expect(scanner2.tokens.items.len == 4);

    var scanner3 = getTokens(a, "<div>Hello World</div>");
    defer scannerForTestDeinit(&scanner3);
    try expect(scanner3.tokens.items.len == 5);

    var scanner4 = getTokens(a, "<script>const a = 1; a < 1; </script>");
    defer scannerForTestDeinit(&scanner4);
    try expect(scanner4.tokens.items.len == 6);

    var scanner5 = getTokens(a, "<div>{\"{}\"Hello { } World }</div>");
    defer scannerForTestDeinit(&scanner5);
    try expect(scanner5.tokens.items.len == 7);

    var scanner6 = getTokens(a, "{#if \"{}\"Hello { } World }");
    defer scannerForTestDeinit(&scanner6);
    try expect(scanner6.tokens.items.len == 5);

    var scanner7 = getTokens(a, "{ /if }");
    defer scannerForTestDeinit(&scanner7);
    try expect(scanner7.tokens.items.len == 5);

    var scanner8 = getTokens(a, "{#if hello world} <div></div> {:else if hello world} {:else Hello} {/if}");
    defer scannerForTestDeinit(&scanner8);
    try expect(scanner8.tokens.items.len == 24);

    var scanner9 = getTokens(a, "{:else if hello world} {:else Hello}");
    defer scannerForTestDeinit(&scanner9);
    try expect(scanner9.tokens.items.len == 10);

    var scanner10 = getTokens(a, "{@html \"<div>Hello World!</div>\"}");
    defer scannerForTestDeinit(&scanner10);
    try expect(scanner10.tokens.items.len == 5);

    var scanner11 = getTokens(a, "{@const \"<div>Hello World!</div>\"}");
    defer scannerForTestDeinit(&scanner11);
    try expect(scanner11.tokens.items.len == 5);

    var scanner12 = getTokens(a, "<div attrKey1={attrVal1} {attrVal2} attrKey3=\"attrValue3\" class:attrVal4>Hello World</div>");
    defer scannerForTestDeinit(&scanner12);
    try expect(scanner12.tokens.items.len == 20);
}
