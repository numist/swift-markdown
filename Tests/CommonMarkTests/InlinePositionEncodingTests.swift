/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Permanent regression net for the DELIVERABLE (flag-OFF) source positions of inline constructs
/// across Unicode encoding classes. The differential fuzzer is dropping position matching, so this
/// suite becomes the sole guard on the shipped parser's inline source ranges.
///
/// A `SourcePosition.column` is a 1-based UTF-8 **byte** offset within its line, so a leading
/// multi-byte scalar advances the column by its byte count (é = 2, € = 3, 😀 = 4, U+FFFD = 3, a
/// combining mark = its own 2 bytes). Every asserted value below was confirmed against the
/// prebuilt `dump --new-off` oracle (the deliverable surface) for the same input plus a `0x00`
/// options byte; that byte selects exactly this option set (`disableSmartOpts` off → `.smart`,
/// `disableSourcePosOpts` off → `.sourcePosition`, GFM tables/strikethrough/tasklist/tableSpans
/// always on, `cmarkBugCompatibility` off), so `Self.opts` == the deliverable configuration.
///
/// Where the deliverable diverges from cmark, cmark is the buggy side; the divergence is annotated
/// `// cmark differs:` with the quirk it stems from and the flag-OFF (spec-correct) value is asserted.
@Suite("Inline source positions — Unicode encodings")
struct InlinePositionEncodingTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The full GFM deliverable configuration, WITHOUT `.cmarkBugCompatibility`. Byte-for-byte the
    /// option set `dump --new-off` uses for a `0x00` options byte (see `CommonMarkConverter`).
    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func nodes(_ src: String) throws -> [InlineNodeInfo] {
        var out: [InlineNodeInfo] = []
        try MarkdownDocument.withParsedDocument(src, options: Self.opts) { doc in
            collectInlineNodes(doc.root, into: &out)
        }
        return out
    }

    private func range(_ l1: Int, _ c1: Int, _ l2: Int, _ c2: Int) -> Range<Pos> {
        Pos(line: l1, column: c1) ..< Pos(line: l2, column: c2)
    }

    // MARK: - Text runs

    @Test("text runs — multibyte / combining / replacement / tab byte accounting")
    func textRuns() throws {
        // ASCII baseline: 3 bytes.
        var n = try nodes("abc")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "abc")
        #expect(n[1].range == range(1, 1, 1, 4))
        #expect(n[2].range == range(1, 1, 1, 4))

        // é(2) + €(3) + 😀(4) = 9 bytes → end column 10.
        n = try nodes("\u{E9}\u{20AC}\u{1F600}")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}\u{20AC}\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 10))

        // Combining é (e + U+0301, 3 bytes) + x = 4 bytes.
        n = try nodes("e\u{301}x")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "e\u{301}x")
        #expect(n[2].range == range(1, 1, 1, 5))

        // U+FFFD replacement char, 3 bytes (also the invalid-UTF-8 repair byte accounting).
        n = try nodes("\u{FFFD}")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 4))

        // A TAB inside a text run stays a 1-byte literal (no inline tab expansion).
        n = try nodes("a\tb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "a\tb")
        #expect(n[2].range == range(1, 1, 1, 4))
    }

    // MARK: - Emphasis (asterisk)

    @Test("emphasis * — leading and interior multibyte shift the byte columns")
    func emphasisAsterisk() throws {
        // Baseline: * at col 1, x at col 2, * at col 3.
        var n = try nodes("*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 2, 1, 3))

        // Leading é (2 bytes) shifts the emphasis to col 3.
        n = try nodes("\u{E9}*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 6))
        #expect(n[4].range == range(1, 4, 1, 5))

        // Interior é: * (col1), é (cols 2-3), * (col4).
        n = try nodes("*\u{E9}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))
        #expect(n[3].range == range(1, 2, 1, 4))

        // Leading € (3 bytes) shifts the emphasis to col 4.
        n = try nodes("\u{20AC}*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{20AC}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 7))
        #expect(n[4].range == range(1, 5, 1, 6))

        // Interior astral 😀 (4 bytes): text spans cols 2-5, end column 6.
        n = try nodes("*\u{1F600}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 7))
        #expect(n[3].range == range(1, 2, 1, 6))

        // Interior combining é (3 bytes): text spans cols 2-4, end column 5.
        n = try nodes("*e\u{301}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "e\u{301}")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 2, 1, 5))

        // Interior U+FFFD (3 bytes).
        n = try nodes("*\u{FFFD}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 2, 1, 5))
    }

    // MARK: - Emphasis (underscore)

    @Test("emphasis _ — interior multibyte and left-flank opening after a multibyte + space")
    func emphasisUnderscore() throws {
        // Baseline.
        var n = try nodes("_x_")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 2, 1, 3))

        // Interior é.
        n = try nodes("_\u{E9}_")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))
        #expect(n[3].range == range(1, 2, 1, 4))

        // "é " then "_x_": the space makes `_` left-flanking (intraword `_` after a letter would
        // NOT open), so emphasis begins at col 4 (é=2 bytes + space).
        n = try nodes("\u{E9} _x_")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{E9} " && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 7))
        #expect(n[4].range == range(1, 5, 1, 6))
    }

    // MARK: - Strong

    @Test("strong ** — leading and interior multibyte shift the byte columns")
    func strong() throws {
        // Baseline: ** (cols 1-2), x (col 3), ** (cols 4-5).
        var n = try nodes("**x**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 3, 1, 4))

        // Leading é (2 bytes) shifts strong to col 3.
        n = try nodes("\u{E9}**x**")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .strong, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 8))
        #expect(n[4].range == range(1, 5, 1, 6))

        // Interior € (3 bytes): text spans cols 3-5, end column 6.
        n = try nodes("**\u{20AC}**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 3, 1, 6))

        // Interior astral 😀 (4 bytes): text spans cols 3-6, end column 7.
        n = try nodes("**\u{1F600}**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 3, 1, 7))
    }

    // MARK: - Code spans

    @Test("code span — range spans the backticks; interior multibyte counts as bytes")
    func codeSpan() throws {
        // Baseline: `x` — the codeInline range spans both backticks (cols 1..3), end column 4.
        var n = try nodes("`x`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))

        // Leading é (2 bytes) shifts the span to col 3.
        n = try nodes("\u{E9}`x`")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{E9}" && n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 6))

        // Interior é (2 bytes): ` (col1), é (cols 2-3), ` (col4), end column 5.
        n = try nodes("`\u{E9}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))

        // Interior € (3 bytes).
        n = try nodes("`\u{20AC}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 6))

        // Interior astral 😀 (4 bytes).
        n = try nodes("`\u{1F600}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 7))

        // Interior combining é (3 bytes).
        n = try nodes("`e\u{301}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "e\u{301}")
        #expect(n[2].range == range(1, 1, 1, 6))

        // Interior U+FFFD (3 bytes).
        n = try nodes("`\u{FFFD}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 6))

        // Interior TAB stays a 1-byte literal inside the span.
        n = try nodes("`a\tb`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "a\tb")
        #expect(n[2].range == range(1, 1, 1, 6))
    }

    // MARK: - Links

    @Test("links — destination/title carry, range spans the whole construct in bytes")
    func links() throws {
        // Baseline [t](/u): link cols 1..7, text "t" at col 2.
        var n = try nodes("[t](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 2, 1, 3))

        // With a title: the title bytes extend the link's source range (title not position-bearing).
        n = try nodes("[t](/u \"ti\")")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "ti" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 13))
        #expect(n[3].range == range(1, 2, 1, 3))

        // Leading é (2 bytes) shifts the link to col 3.
        n = try nodes("\u{E9}[t](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "/u" && n[4].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 10))
        #expect(n[4].range == range(1, 4, 1, 5))

        // Multibyte in the link text: é (cols 2-3), € (cols 2-4), 😀 (cols 2-5).
        n = try nodes("[\u{E9}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 2, 1, 4))

        n = try nodes("[\u{20AC}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 10))
        #expect(n[3].range == range(1, 2, 1, 5))

        n = try nodes("[\u{1F600}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 11))
        #expect(n[3].range == range(1, 2, 1, 6))

        // Multibyte in the title (é = 2 bytes, same width as the ASCII "ti"): link range unchanged
        // at 1..12, text "t" unchanged; the title decodes to "é".
        n = try nodes("[t](/u \"\u{E9}\")")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "\u{E9}" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 13))
        #expect(n[3].range == range(1, 2, 1, 3))
    }

    // MARK: - Images

    @Test("images — `![` opener widens the source range by one byte vs a link")
    func images() throws {
        // Baseline ![a](/u): image cols 1..8, alt text "a" at col 3 (after `![`).
        var n = try nodes("![a](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[2].url == "/u" && n[3].literal == "a")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 3, 1, 4))

        // Leading é (2 bytes) shifts the image to col 3.
        n = try nodes("\u{E9}![a](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .image, .text])
        try #require(n[3].url == "/u" && n[4].literal == "a")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 11))
        #expect(n[4].range == range(1, 5, 1, 6))

        // Multibyte alt text: é (cols 3-4), 😀 (cols 3-6).
        n = try nodes("![\u{E9}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 10))
        #expect(n[3].range == range(1, 3, 1, 5))

        n = try nodes("![\u{1F600}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 12))
        #expect(n[3].range == range(1, 3, 1, 7))
    }

    // MARK: - Autolinks

    @Test("autolinks — URI and email; leading multibyte shifts the byte columns")
    func autolinks() throws {
        // <http://x>: link cols 1..10 (over the angle brackets), inner text cols 2..9.
        var n = try nodes("<http://x>")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "http://x" && n[3].literal == "http://x")
        #expect(n[2].range == range(1, 1, 1, 11))
        #expect(n[3].range == range(1, 2, 1, 10))

        // Leading é (2 bytes) shifts the autolink to col 3.
        n = try nodes("\u{E9}<http://x>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "http://x" && n[4].literal == "http://x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 13))
        #expect(n[4].range == range(1, 4, 1, 12))

        // Email autolink: destination gets a "mailto:" prefix; the range still spans the source.
        n = try nodes("<a@b.c>")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "mailto:a@b.c" && n[3].literal == "a@b.c")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 2, 1, 7))

        // Leading € (3 bytes) shifts the email autolink to col 4.
        n = try nodes("\u{20AC}<a@b.c>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "mailto:a@b.c" && n[4].literal == "a@b.c")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 11))
        #expect(n[4].range == range(1, 5, 1, 10))
    }

    // MARK: - Inline HTML

    @Test("inline HTML — <span> tag range in bytes with a leading/interior multibyte")
    func inlineHTML() throws {
        // Leading é keeps `<span>` inline (a `<` at line start would open an HTML block instead).
        var n = try nodes("\u{E9}<span>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline])
        try #require(n[2].literal == "\u{E9}" && n[3].literal == "<span>")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 9))

        // Text on both sides: a (col1), <span> (cols 2-7), b (col8).
        n = try nodes("a<span>b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        try #require(n[2].literal == "a" && n[3].literal == "<span>" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == range(1, 2, 1, 8))
        #expect(n[4].range == range(1, 8, 1, 9))

        // Leading € (3 bytes) shifts the tag to col 4.
        n = try nodes("\u{20AC}<span>b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        try #require(n[2].literal == "\u{20AC}" && n[3].literal == "<span>" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 10))
        #expect(n[4].range == range(1, 10, 1, 11))
    }

    // MARK: - Entities

    @Test("entities — source range spans the raw entity bytes; literal is the decoded scalar")
    func entities() throws {
        // &amp; → "&": 5 raw source bytes (cols 1..5), literal one char.
        var n = try nodes("&amp;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "&")
        #expect(n[2].range == range(1, 1, 1, 6))

        // Numeric &#233; → "é": 6 raw bytes.
        n = try nodes("&#233;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 7))

        // Named &ouml; → "ö": 6 raw bytes.
        n = try nodes("&ouml;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{F6}")
        #expect(n[2].range == range(1, 1, 1, 7))

        // Leading é (2 bytes) then &amp;: one merged text node "é&", cols 1..7, end column 8.
        n = try nodes("\u{E9}&amp;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}&")
        #expect(n[2].range == range(1, 1, 1, 8))
    }

    // MARK: - Hard breaks (two trailing spaces)

    @Test("hard break (two spaces) — preceding text owns the trailing spaces; break carries no range")
    func hardBreakTwoSpaces() throws {
        // "a  \nb": text "a" range extends over the 2 stripped spaces to col 4 (literal still "a");
        // the LineBreak has no source range; "b" is line 2 col 1.
        var n = try nodes("a  \nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        // Leading é (2 bytes): text "é" spans cols 1-2 and its range extends to col 5 over the spaces.
        n = try nodes("\u{E9}  \nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 5))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        // Multibyte on the second line: "€b" spans line-2 cols 1..4, end column 5.
        n = try nodes("a  \n\u{20AC}b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "\u{20AC}b")
        #expect(n[1].range == range(1, 1, 2, 5))
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 5))
    }

    // MARK: - Hard breaks (backslash) — DELIVERABLE-CORRECT / cmark-buggy

    @Test("hard break (backslash) — following text is on line 2 (cmark keeps it on line 1: Quirk D)")
    func hardBreakBackslash() throws {
        // "a\\\nb": the `\` (col 2) is consumed into the LineBreak, so text "a" stops at col 2.
        // The following text "b" is line 2 col 1 (spec-correct).
        // cmark differs: Text "b" @1:4-1:5 — quirk D (cmark's backslash hard break does not reset
        // its inline column cursor, so "b" keeps a flat line-1 column; the deliverable advances the line).
        var n = try nodes("a\\\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        // Leading é (2 bytes): text "é" cols 1-2, `\` at col 3; following "b" is line 2 col 1.
        // cmark differs: Text "b" @1:5-1:6 — quirk D.
        n = try nodes("\u{E9}\\\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))
    }

    // MARK: - Soft breaks

    @Test("soft break — line advance; break carries no range; multibyte on either line")
    func softBreak() throws {
        // "a\nb": text "a" cols 1-2 (owns nothing extra), SoftBreak no range, "b" line 2 col 1.
        var n = try nodes("a\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        // Leading é (2 bytes): text "é" cols 1-2, end column 3.
        n = try nodes("\u{E9}\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        // Multibyte on the second line: "€b" line-2 cols 1..4, end column 5.
        n = try nodes("a\n\u{20AC}b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "\u{20AC}b")
        #expect(n[1].range == range(1, 1, 2, 5))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 5))
    }
}

/// A copyable snapshot of a `MarkdownNode` for DFS assertions (the node itself is `~Escapable`).
private struct InlineNodeInfo {
    let kind: MarkdownNode.Kind
    let literal: String?
    let url: String?
    let title: String?
    let range: Range<MarkdownNode.SourcePosition>?
}

// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (matches the other
// source-position suites' DFS collectors). `literal()`, `url()`, `title()` are the test-target
// helpers in `NodeContentLegacyHelpers.swift`.
private func collectInlineNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [InlineNodeInfo]
) {
    out.append(
        InlineNodeInfo(
            kind: node.kind,
            literal: node.literal(),
            url: node.url(),
            title: node.title(),
            range: node.sourceRange
        )
    )
    node.children.forEach { child in
        collectInlineNodes(child, into: &out)
    }
}
