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

/// GFM `://`-scheme (and `www.`) autolink URL boundary + trailing-punctuation rules, mirroring
/// cmark-gfm's `url_match` / `www_match` (URL body scan) and `autolink_delim` (trailing trim) in
/// `extensions/autolink.c`.
///
/// Body scan: a URL runs to the first `cmark_isspace` byte (space, tab, LF, CR only) or `<`. `>` is NOT
/// a boundary and stays in the URL; VT/FF are not `cmark_isspace` and also stay in the URL.
///
/// Trailing trim (`autolink_delim`, applied from the end): `? ! . , : * _ ~ ' "` are peeled one at a
/// time; a `)` is peeled only when the URL holds more `)` than `(`; a trailing `;` peels a whole
/// `&`+ASCII-letters+`;` entity tail when present, otherwise just the `;`.
@Suite("GFM autolink URL boundary and trailing punctuation")
struct AutolinkURLDelimiterTests {

    /// The shipped configuration: GFM autolink on. The boundary/trim rules are unconditional (GFM is
    /// cmark-defined), so they are identical flag-ON and flag-OFF; this exercises the clean deliverable tree.
    private static let flagOn: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - The two fuzzer hits

    @Test("hit: `http://l>` keeps the trailing `>` in the URL")
    func hitGreaterThanKept() throws {
        // cmark's URL body scan ends only at whitespace or `<`; `>` is an ordinary URL byte and
        // `autolink_delim` never trims it, so the whole `http://l>` is the link.
        let ns = try nodes(in: "http://l>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l>"])
        #expect(ns.compactMap(\.url) == ["http://l>"])
    }

    @Test("hit: `http://m'` trims the trailing `'`")
    func hitApostropheTrimmed() throws {
        // `'` is in cmark's `autolink_delim` peel set, so it is split off as text.
        let ns = try nodes(in: "http://m'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://m", "'"])
        #expect(ns.compactMap(\.url) == ["http://m"])
    }

    // MARK: - Each diverging trailing/boundary character

    @Test("`>` is kept as a URL byte, not a boundary")
    func greaterThanKept() throws {
        let ns = try nodes(in: "http://l>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://l>"])
    }

    @Test("trailing `'` is trimmed")
    func apostropheTrimmed() throws {
        let ns = try nodes(in: "http://l'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", "'"])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("trailing `\"` is trimmed")
    func doubleQuoteTrimmed() throws {
        let ns = try nodes(in: "http://l\"", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", "\""])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("trailing `;` with no entity is trimmed")
    func semicolonTrimmed() throws {
        // No `&` precedes the `;`, so cmark's `autolink_delim` falls to its `else link_end--` branch and
        // drops just the `;` (the rewrite previously kept it, only trimming a matched `&…;`).
        let ns = try nodes(in: "http://l;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", ";"])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    // MARK: - Entity-aware `;` handling

    @Test("trailing `&…;` entity tail (letters only) is split off whole")
    func semicolonEntityStripped() throws {
        // `&zq;` is `&` + ASCII letters + `;`; cmark's back-scan finds the `&` and removes the whole tail.
        // `&zq;` is not a recognized entity, so the split-off text stays literal.
        let ns = try nodes(in: "http://x/&zq;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://x/", "&zq;"])
        #expect(ns.compactMap(\.url) == ["http://x/"])
    }

    @Test("trailing `&…;` with a digit is NOT an entity: only the `;` is trimmed")
    func semicolonEntityWithDigitOnlyTrimsSemicolon() throws {
        // cmark's `;` back-scan uses `cmark_isalpha` (letters only). `&am2;` has a digit, so the scan stops
        // at `2` (not the `&`) and only the `;` is dropped; `&am2` stays in the URL.
        let ns = try nodes(in: "http://l/&am2;", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l/&am2", ";"])
        #expect(ns.compactMap(\.url) == ["http://l/&am2"])
    }

    // MARK: - Multi-trailing sequences

    @Test("`http://l');` peels `;`, then the unbalanced `)`, then `'`")
    func multiTrailingApostropheParenSemicolon() throws {
        let ns = try nodes(in: "http://l');", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", "');"])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("`http://l>.` keeps `>` and trims the trailing `.`")
    func multiTrailingGreaterThanDot() throws {
        let ns = try nodes(in: "http://l>.", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l>", "."])
        #expect(ns.compactMap(\.url) == ["http://l>"])
    }

    @Test("`http://l>>` keeps both trailing `>`")
    func multiTrailingDoubleGreaterThan() throws {
        let ns = try nodes(in: "http://l>>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l>>"])
        #expect(ns.compactMap(\.url) == ["http://l>>"])
    }

    // MARK: - VT/FF are not cmark whitespace: kept in the URL

    @Test("a trailing vertical tab (0x0B) stays in the URL")
    func verticalTabKept() throws {
        // cmark's body scan uses `cmark_isspace`, which excludes VT (0x0B); the rewrite must not treat it
        // as a boundary (its HTML `isASCIISpace` does, which was the bug).
        let ns = try nodes(in: "http://l\u{0B}", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://l\u{0B}"])
    }

    @Test("a trailing form feed (0x0C) stays in the URL")
    func formFeedKept() throws {
        let ns = try nodes(in: "http://l\u{0C}", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://l\u{0C}"])
    }

    // MARK: - Regression controls (already matching cmark; must stay matching)

    @Test("control: trailing `.` is trimmed")
    func controlDotTrimmed() throws {
        let ns = try nodes(in: "http://l.", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", "."])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("control: trailing `!` is trimmed")
    func controlBangTrimmed() throws {
        let ns = try nodes(in: "http://l!", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", "!"])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("control: a lone unbalanced trailing `)` is trimmed")
    func controlUnbalancedParenTrimmed() throws {
        let ns = try nodes(in: "http://l)", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://l", ")"])
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("control: `<` ends the URL body")
    func controlLessThanBoundary() throws {
        let ns = try nodes(in: "http://l<", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.compactMap(\.url) == ["http://l"])
    }

    @Test("control: balanced parentheses are kept")
    func controlBalancedParensKept() throws {
        let ns = try nodes(in: "http://e.com/(a)", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("control: only the extra unbalanced `)` is trimmed")
    func controlExtraParenTrimmed() throws {
        let ns = try nodes(in: "http://e.com/(a))", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e.com/(a)", ")"])
        #expect(ns.compactMap(\.url) == ["http://e.com/(a)"])
    }

    @Test("control: the remaining peel-set characters `, ? : * _ ~` are each trimmed")
    func controlRemainingPeelSetTrimmed() throws {
        // The rest of cmark's `autolink_delim` peel set, one per case, so every member is exercised
        // directly rather than only via a shared switch arm. Each splits off as trailing text.
        for ch in [",", "?", ":", "*", "_", "~"] {
            let ns = try nodes(in: "http://l" + ch, options: Self.flagOn)
            try #require(ns.map(\.kind).contains(.link))
            #expect(ns.map(\.text) == [nil, nil, nil, "http://l", ch])
            #expect(ns.compactMap(\.url) == ["http://l"])
        }
    }

    // MARK: - `www.` form shares the same body scan + trim

    @Test("www: trailing `'` is trimmed (shared trim)")
    func wwwApostropheTrimmed() throws {
        let ns = try nodes(in: "www.a.b'", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", "'"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    @Test("www: trailing `>` is kept (shared body scan)")
    func wwwGreaterThanKept() throws {
        let ns = try nodes(in: "www.a.b>", options: Self.flagOn)
        try #require(ns.map(\.kind).contains(.link))
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b>"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b>"])
    }
}
