/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind, text literal, and (for links) destination URL.
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// After its domain, an extended url or www autolink runs to the first space or `<` (Autolinks (extension)), so
/// `>` is part of it. Extended autolink path validation then removes trailing `? ! . , : * _ ~`, an unmatched
/// trailing `)`, and a trailing `&` + ASCII letters + `;`; the parser also removes a trailing `'`, `"` or other `;`.
@Suite("Extended autolink end and trailing punctuation")
struct AutolinkURLDelimiterTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    @Test("`http://a.l>` links with the `>` in its text")
    func greaterThanKeptInLinkText() throws {
        let ns = nodes(in: "http://a.l>", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>"])
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("`http://a.m'` links with the `'` as trailing text")
    func apostropheTrimmedToText() throws {
        let ns = nodes(in: "http://a.m'", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.m", "'"])
        #expect(ns.compactMap(\.url) == ["http://a.m"])
    }

    // MARK: - Trailing characters

    @Test("`>` is part of the URL")
    func greaterThanKept() throws {
        let ns = nodes(in: "http://a.l>", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("trailing `'` is trimmed")
    func apostropheTrimmed() throws {
        let ns = nodes(in: "http://a.l'", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "'"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("trailing `\"` is trimmed")
    func doubleQuoteTrimmed() throws {
        let ns = nodes(in: "http://a.l\"", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "\""])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("trailing `;` with no entity is trimmed")
    func semicolonTrimmed() throws {
        let ns = nodes(in: "http://a.l;", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ";"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    // MARK: - Entity-like `;` tails

    @Test("a trailing `&` + alphanumerics + `;` is removed whole")
    func semicolonEntityStripped() throws {
        // `&zq;` is not an entity reference, so the trailing text is literal.
        let ns = nodes(in: "http://a.x/&zq;", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.x/", "&zq;"])
        #expect(ns.compactMap(\.url) == ["http://a.x/"])
    }

    @Test("with a digit between `&` and `;`, the tail is removed whole")
    func semicolonEntityWithDigitStripped() throws {
        let ns = nodes(in: "http://a.l/&am2;", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l/", "&am2;"])
        #expect(ns.compactMap(\.url) == ["http://a.l/"])
    }

    // MARK: - Multi-trailing sequences

    @Test("`http://a.l');` removes `;`, then the unbalanced `)`, then `'`")
    func multiTrailingApostropheParenSemicolon() throws {
        let ns = nodes(in: "http://a.l');", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "');"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("`http://a.l>.` keeps `>` and trims the trailing `.`")
    func multiTrailingGreaterThanDot() throws {
        let ns = nodes(in: "http://a.l>.", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>", "."])
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("`http://a.l>>` keeps both trailing `>`")
    func multiTrailingDoubleGreaterThan() throws {
        let ns = nodes(in: "http://a.l>>", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>>"])
        #expect(ns.compactMap(\.url) == ["http://a.l>>"])
    }

    // MARK: - Whitespace at the end of a paragraph

    // The paragraph's raw content has its final whitespace removed, and the spec's whitespace includes
    // line tabulation and form feed (spec "Paragraphs"), so neither ends the URL.

    @Test("a trailing vertical tab (0x0B) is not part of the URL")
    func verticalTabRemoved() throws {
        let ns = nodes(in: "http://a.l\u{0B}", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("a trailing form feed (0x0C) is not part of the URL")
    func formFeedRemoved() throws {
        let ns = nodes(in: "http://a.l\u{0C}", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    // MARK: - Trailing punctuation and parentheses

    @Test("trailing `.` is trimmed")
    func dotTrimmed() throws {
        let ns = nodes(in: "http://a.l.", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "."])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("trailing `!` is trimmed")
    func bangTrimmed() throws {
        let ns = nodes(in: "http://a.l!", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "!"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("a lone unbalanced trailing `)` is trimmed")
    func unbalancedParenTrimmed() throws {
        let ns = nodes(in: "http://a.l)", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ")"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("`<` ends the URL")
    func lessThanBoundary() throws {
        let ns = nodes(in: "http://a.l<", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("balanced parentheses are kept")
    func balancedParensKept() throws {
        let ns = nodes(in: "http://e.com/(a)", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("only the extra unbalanced `)` is trimmed")
    func extraParenTrimmed() throws {
        let ns = nodes(in: "http://e.com/(a))", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e.com/(a)", ")"])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("trailing `,`, `?`, `:`, `*`, `_` and `~` are each trimmed")
    func remainingTrailingPunctuationTrimmed() throws {
        for ch in [",", "?", ":", "*", "_", "~"] {
            let ns = nodes(in: "http://a.l" + ch, options: Self.options)
            try #require(ns.map(\.kind).contains(.link))
            #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ch])
            #expect(ns.compactMap(\.url) == ["http://a.l"])
        }
    }

    // MARK: - Extended www autolinks

    @Test("www: trailing `'` is trimmed")
    func wwwApostropheTrimmed() throws {
        let ns = nodes(in: "www.a.b'", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", "'"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    @Test("www: trailing `>` is kept")
    func wwwGreaterThanKept() throws {
        let ns = nodes(in: "www.a.b>", options: Self.options)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b>"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b>"])
    }
}
