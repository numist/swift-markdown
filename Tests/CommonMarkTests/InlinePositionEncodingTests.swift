/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Inline source positions of multi-byte scalars")
struct InlinePositionEncodingTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let opts: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func nodes(_ src: String) -> [InlineNodeInfo] {
        var out: [InlineNodeInfo] = []
        MarkdownDocument.withParsedDocument(src, options: Self.opts) { doc in
            collectInlineNodes(doc.root, into: &out)
        }
        return out
    }

    private func range(_ l1: Int, _ c1: Int, _ l2: Int, _ c2: Int) -> Range<Pos> {
        Pos(line: l1, column: c1) ..< Pos(line: l2, column: c2)
    }

    @Test("text runs — multibyte / combining / replacement / tab byte accounting")
    func textRuns() throws {
        var n = nodes("abc")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "abc")
        #expect(n[1].range == range(1, 1, 1, 4))
        #expect(n[2].range == range(1, 1, 1, 4))

        n = nodes("\u{E9}\u{20AC}\u{1F600}")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}\u{20AC}\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 10))

        n = nodes("e\u{301}x")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "e\u{301}x")
        #expect(n[2].range == range(1, 1, 1, 5))

        n = nodes("\u{FFFD}")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 4))

        n = nodes("a\tb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "a\tb")
        #expect(n[2].range == range(1, 1, 1, 4))
    }

    @Test("emphasis * — leading and interior multibyte shift the byte columns")
    func emphasisAsterisk() throws {
        var n = nodes("*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 2, 1, 3))

        n = nodes("\u{E9}*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 6))
        #expect(n[4].range == range(1, 4, 1, 5))

        n = nodes("*\u{E9}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))
        #expect(n[3].range == range(1, 2, 1, 4))

        n = nodes("\u{20AC}*x*")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{20AC}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 7))
        #expect(n[4].range == range(1, 5, 1, 6))

        n = nodes("*\u{1F600}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 7))
        #expect(n[3].range == range(1, 2, 1, 6))

        n = nodes("*e\u{301}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "e\u{301}")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 2, 1, 5))

        n = nodes("*\u{FFFD}*")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 2, 1, 5))
    }

    @Test("emphasis _ — interior multibyte and left-flank opening after a multibyte + space")
    func emphasisUnderscore() throws {
        var n = nodes("_x_")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 2, 1, 3))

        n = nodes("_\u{E9}_")
        try #require(n.map(\.kind) == [.document, .paragraph, .emphasis, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))
        #expect(n[3].range == range(1, 2, 1, 4))

        // The space lets the `_` open; directly after the é it would be intraword and could not (Emphasis and strong
        // emphasis).
        n = nodes("\u{E9} _x_")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .emphasis, .text])
        try #require(n[2].literal == "\u{E9} " && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 7))
        #expect(n[4].range == range(1, 5, 1, 6))
    }

    @Test("strong ** — leading and interior multibyte shift the byte columns")
    func strong() throws {
        var n = nodes("**x**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 6))
        #expect(n[3].range == range(1, 3, 1, 4))

        n = nodes("\u{E9}**x**")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .strong, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 8))
        #expect(n[4].range == range(1, 5, 1, 6))

        n = nodes("**\u{20AC}**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 3, 1, 6))

        n = nodes("**\u{1F600}**")
        try #require(n.map(\.kind) == [.document, .paragraph, .strong, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 3, 1, 7))
    }

    @Test("code span — range spans the backticks; interior multibyte counts as bytes")
    func codeSpan() throws {
        var n = nodes("`x`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 4))

        n = nodes("\u{E9}`x`")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{E9}" && n[3].literal == "x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 6))

        n = nodes("`\u{E9}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 5))

        n = nodes("`\u{20AC}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 6))

        n = nodes("`\u{1F600}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 7))

        n = nodes("`e\u{301}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "e\u{301}")
        #expect(n[2].range == range(1, 1, 1, 6))

        n = nodes("`\u{FFFD}`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "\u{FFFD}")
        #expect(n[2].range == range(1, 1, 1, 6))

        n = nodes("`a\tb`")
        try #require(n.map(\.kind) == [.document, .paragraph, .codeInline(backtickCount: 1)])
        try #require(n[2].literal == "a\tb")
        #expect(n[2].range == range(1, 1, 1, 6))
    }

    @Test("links — destination/title carry, range spans the whole construct in bytes")
    func links() throws {
        var n = nodes("[t](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 2, 1, 3))

        n = nodes("[t](/u \"ti\")")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "ti" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 13))
        #expect(n[3].range == range(1, 2, 1, 3))

        n = nodes("\u{E9}[t](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "/u" && n[4].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 10))
        #expect(n[4].range == range(1, 4, 1, 5))

        n = nodes("[\u{E9}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 2, 1, 4))

        n = nodes("[\u{20AC}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{20AC}")
        #expect(n[2].range == range(1, 1, 1, 10))
        #expect(n[3].range == range(1, 2, 1, 5))

        n = nodes("[\u{1F600}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 11))
        #expect(n[3].range == range(1, 2, 1, 6))

        n = nodes("[t](/u \"\u{E9}\")")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "/u" && n[2].title == "\u{E9}" && n[3].literal == "t")
        #expect(n[2].range == range(1, 1, 1, 13))
        #expect(n[3].range == range(1, 2, 1, 3))
    }

    @Test("images — `![` opener widens the source range by one byte vs a link")
    func images() throws {
        var n = nodes("![a](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[2].url == "/u" && n[3].literal == "a")
        #expect(n[2].range == range(1, 1, 1, 9))
        #expect(n[3].range == range(1, 3, 1, 4))

        n = nodes("\u{E9}![a](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .image, .text])
        try #require(n[3].url == "/u" && n[4].literal == "a")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 11))
        #expect(n[4].range == range(1, 5, 1, 6))

        n = nodes("![\u{E9}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[3].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 10))
        #expect(n[3].range == range(1, 3, 1, 5))

        n = nodes("![\u{1F600}](/u)")
        try #require(n.map(\.kind) == [.document, .paragraph, .image, .text])
        try #require(n[3].literal == "\u{1F600}")
        #expect(n[2].range == range(1, 1, 1, 12))
        #expect(n[3].range == range(1, 3, 1, 7))
    }

    @Test("autolinks — URI and email; leading multibyte shifts the byte columns")
    func autolinks() throws {
        var n = nodes("<http://x>")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "http://x" && n[3].literal == "http://x")
        #expect(n[2].range == range(1, 1, 1, 11))
        #expect(n[3].range == range(1, 2, 1, 10))

        n = nodes("\u{E9}<http://x>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "http://x" && n[4].literal == "http://x")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 13))
        #expect(n[4].range == range(1, 4, 1, 12))

        n = nodes("<a@b.c>")
        try #require(n.map(\.kind) == [.document, .paragraph, .link, .text])
        try #require(n[2].url == "mailto:a@b.c" && n[3].literal == "a@b.c")
        #expect(n[2].range == range(1, 1, 1, 8))
        #expect(n[3].range == range(1, 2, 1, 7))

        n = nodes("\u{20AC}<a@b.c>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        try #require(n[3].url == "mailto:a@b.c" && n[4].literal == "a@b.c")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 11))
        #expect(n[4].range == range(1, 5, 1, 10))
    }

    @Test("inline HTML — <span> tag range in bytes with a leading/interior multibyte")
    func inlineHTML() throws {
        // The leading é keeps `<span>` inline; at the start of a line it would start an HTML block (HTML blocks).
        var n = nodes("\u{E9}<span>")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline])
        try #require(n[2].literal == "\u{E9}" && n[3].literal == "<span>")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == range(1, 3, 1, 9))

        n = nodes("a<span>b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        try #require(n[2].literal == "a" && n[3].literal == "<span>" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == range(1, 2, 1, 8))
        #expect(n[4].range == range(1, 8, 1, 9))

        n = nodes("\u{20AC}<span>b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        try #require(n[2].literal == "\u{20AC}" && n[3].literal == "<span>" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 4))
        #expect(n[3].range == range(1, 4, 1, 10))
        #expect(n[4].range == range(1, 10, 1, 11))

        n = nodes("a<span title=\"\u{E9}\">b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .htmlInline, .text])
        try #require(n[2].literal == "a" && n[3].literal == "<span title=\"\u{E9}\">" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == range(1, 2, 1, 19))
        #expect(n[4].range == range(1, 19, 1, 20))
    }

    @Test("character references — source range spans the reference; literal is the decoded scalar")
    func entities() throws {
        var n = nodes("&amp;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "&")
        #expect(n[2].range == range(1, 1, 1, 6))

        n = nodes("&#233;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}")
        #expect(n[2].range == range(1, 1, 1, 7))

        n = nodes("&ouml;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{F6}")
        #expect(n[2].range == range(1, 1, 1, 7))

        n = nodes("\u{E9}&amp;")
        try #require(n.map(\.kind) == [.document, .paragraph, .text])
        try #require(n[2].literal == "\u{E9}&")
        #expect(n[2].range == range(1, 1, 1, 8))
    }

    @Test("hard line break (two spaces) — preceding text ends at its content; break carries no range")
    func hardBreakTwoSpaces() throws {
        var n = nodes("a  \nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        n = nodes("\u{E9}  \nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        n = nodes("a  \n\u{20AC}b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "\u{20AC}b")
        #expect(n[1].range == range(1, 1, 2, 5))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 5))
    }

    @Test("hard line break (backslash) — following text is on line 2")
    func hardBreakBackslash() throws {
        var n = nodes("a\\\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        n = nodes("\u{E9}\\\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .lineBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))
    }

    @Test("soft line break — line advance; break carries no range; multibyte on either line")
    func softBreak() throws {
        var n = nodes("a\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "b")
        #expect(n[1].range == range(1, 1, 2, 2))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        n = nodes("\u{E9}\nb")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "\u{E9}" && n[4].literal == "b")
        #expect(n[2].range == range(1, 1, 1, 3))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 2))

        n = nodes("a\n\u{20AC}b")
        try #require(n.map(\.kind) == [.document, .paragraph, .text, .softBreak, .text])
        try #require(n[2].literal == "a" && n[4].literal == "\u{20AC}b")
        #expect(n[1].range == range(1, 1, 2, 5))
        #expect(n[2].range == range(1, 1, 1, 2))
        #expect(n[3].range == nil)
        #expect(n[4].range == range(2, 1, 2, 5))
    }
}

private struct InlineNodeInfo {
    let kind: MarkdownNode.Kind
    let literal: String?
    let url: String?
    let title: String?
    let range: Range<MarkdownNode.SourcePosition>?
}

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
