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

/// GFM `://`-scheme (and `www.`) autolink URL boundary + trailing-punctuation rules (spec "Autolinks
/// (extension)"): after a valid domain, a URL runs to the first space or `<`; trailing `? ! . , : * _ ~`
/// are not part of it, nor is an unmatched trailing `)` or an entity-like `&name;` tail.
@Suite("GFM autolink URL boundary and trailing punctuation")
struct AutolinkURLDelimiterTests {

    /// The shipped configuration: GFM autolink on. The boundary/trim rules are unconditional (GFM is
    /// cmark-defined), so they are identical flag-ON and flag-OFF; this exercises the clean deliverable tree.
    private static let flagOn: MarkdownDocument.ParseOptions = [.gfmAutolink]

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

    // MARK: - The two fuzzer hits

    @Test("hit: `http://a.l>` keeps the trailing `>` in the URL")
    func hitGreaterThanKept() throws {
        // cmark's URL body scan ends only at whitespace or `<`; `>` is an ordinary URL byte and
        // `autolink_delim` never trims it, so the whole `http://a.l>` is the link.
        let ns = nodes(in: "http://a.l>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>"])
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("hit: `http://a.m'` trims the trailing `'`")
    func hitApostropheTrimmed() throws {
        // `'` is in cmark's `autolink_delim` peel set, so it is split off as text.
        let ns = nodes(in: "http://a.m'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.m", "'"])
        #expect(ns.compactMap(\.url) == ["http://a.m"])
    }

    // MARK: - Each diverging trailing/boundary character

    @Test("`>` is kept as a URL byte, not a boundary")
    func greaterThanKept() throws {
        let ns = nodes(in: "http://a.l>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("trailing `'` is trimmed")
    func apostropheTrimmed() throws {
        let ns = nodes(in: "http://a.l'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "'"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("trailing `\"` is trimmed")
    func doubleQuoteTrimmed() throws {
        let ns = nodes(in: "http://a.l\"", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "\""])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("trailing `;` with no entity is trimmed")
    func semicolonTrimmed() throws {
        // No `&` precedes the `;`, so cmark's `autolink_delim` falls to its `else link_end--` branch and
        // drops just the `;` (the rewrite previously kept it, only trimming a matched `&…;`).
        let ns = nodes(in: "http://a.l;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ";"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    // MARK: - Entity-aware `;` handling

    @Test("trailing `&…;` entity tail (letters only) is split off whole")
    func semicolonEntityStripped() throws {
        // `&zq;` is `&` + ASCII letters + `;`; cmark's back-scan finds the `&` and removes the whole tail.
        // `&zq;` is not a recognized entity, so the split-off text stays literal.
        let ns = nodes(in: "http://a.x/&zq;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.x/", "&zq;"])
        #expect(ns.compactMap(\.url) == ["http://a.x/"])
    }

    @Test("trailing `&…;` with a digit is NOT an entity: only the `;` is trimmed")
    func semicolonEntityWithDigitOnlyTrimsSemicolon() throws {
        // cmark's `;` back-scan uses `cmark_isalpha` (letters only). `&am2;` has a digit, so the scan stops
        // at `2` (not the `&`) and only the `;` is dropped; `&am2` stays in the URL.
        let ns = nodes(in: "http://a.l/&am2;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l/&am2", ";"])
        #expect(ns.compactMap(\.url) == ["http://a.l/&am2"])
    }

    // MARK: - Multi-trailing sequences

    @Test("`http://a.l');` peels `;`, then the unbalanced `)`, then `'`")
    func multiTrailingApostropheParenSemicolon() throws {
        let ns = nodes(in: "http://a.l');", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "');"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("`http://a.l>.` keeps `>` and trims the trailing `.`")
    func multiTrailingGreaterThanDot() throws {
        let ns = nodes(in: "http://a.l>.", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>", "."])
        #expect(ns.compactMap(\.url) == ["http://a.l>"])
    }

    @Test("`http://a.l>>` keeps both trailing `>`")
    func multiTrailingDoubleGreaterThan() throws {
        let ns = nodes(in: "http://a.l>>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l>>"])
        #expect(ns.compactMap(\.url) == ["http://a.l>>"])
    }

    // MARK: - A paragraph's final VT/FF is removed before the URL is scanned

    // The paragraph's raw content has its final whitespace removed, and the spec's whitespace includes
    // line tabulation and form feed (spec "Paragraphs"), so neither ends the URL.

    @Test("a trailing vertical tab (0x0B) is not part of the URL")
    func verticalTabRemoved() throws {
        let ns = nodes(in: "http://a.l\u{0B}", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("a trailing form feed (0x0C) is not part of the URL")
    func formFeedRemoved() throws {
        let ns = nodes(in: "http://a.l\u{0C}", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    // MARK: - Regression controls (already matching cmark; must stay matching)

    @Test("control: trailing `.` is trimmed")
    func controlDotTrimmed() throws {
        let ns = nodes(in: "http://a.l.", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "."])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("control: trailing `!` is trimmed")
    func controlBangTrimmed() throws {
        let ns = nodes(in: "http://a.l!", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", "!"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("control: a lone unbalanced trailing `)` is trimmed")
    func controlUnbalancedParenTrimmed() throws {
        let ns = nodes(in: "http://a.l)", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ")"])
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("control: `<` ends the URL body")
    func controlLessThanBoundary() throws {
        let ns = nodes(in: "http://a.l<", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://a.l"])
    }

    @Test("control: balanced parentheses are kept")
    func controlBalancedParensKept() throws {
        let ns = nodes(in: "http://e.com/(a)", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("control: only the extra unbalanced `)` is trimmed")
    func controlExtraParenTrimmed() throws {
        let ns = nodes(in: "http://e.com/(a))", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e.com/(a)", ")"])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("control: the remaining peel-set characters `, ? : * _ ~` are each trimmed")
    func controlRemainingPeelSetTrimmed() throws {
        // The rest of cmark's `autolink_delim` peel set, one per case, so every member is exercised
        // directly rather than only via a shared switch arm. Each splits off as trailing text.
        for ch in [",", "?", ":", "*", "_", "~"] {
            let ns = nodes(in: "http://a.l" + ch, options: Self.flagOn)
            try #require(ns.map(\.kind).contains(.link))
            #expect(ns.map(\.text) == [nil, nil, nil, "http://a.l", ch])
            #expect(ns.compactMap(\.url) == ["http://a.l"])
        }
    }

    // MARK: - `www.` form shares the same body scan + trim

    @Test("www: trailing `'` is trimmed (shared trim)")
    func wwwApostropheTrimmed() throws {
        let ns = nodes(in: "www.a.b'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", "'"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    @Test("www: trailing `>` is kept (shared body scan)")
    func wwwGreaterThanKept() throws {
        let ns = nodes(in: "www.a.b>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b>"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b>"])
    }
}
