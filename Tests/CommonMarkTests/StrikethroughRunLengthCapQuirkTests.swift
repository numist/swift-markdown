/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Concatenate every TEXT node's literal within `node`'s subtree, depth-first. File-scope helpers with
// `borrowing MarkdownNode` satisfy the noncopyable-borrow rules (the borrow can't be captured across
// the tree walk) — same pattern as `TaskListCheckboxStrstrQuirkTests`.
private func concatText(_ node: borrowing MarkdownNode, into out: inout String) {
    if case .text = node.kind, case .text(let s) = node.stringContent {
        out += s
    }
    node.children.forEach { child in
        concatText(child, into: &out)
    }
}

// The concatenated inner text of the first `.strikethrough` node (DFS), or nil if none forms.
private func firstStrikethroughText(_ node: borrowing MarkdownNode) -> String? {
    if case .strikethrough = node.kind {
        var out = ""
        concatText(node, into: &out)
        return out
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstStrikethroughText(child)
        }
    }
    return found
}

// The number of `.strikethrough` nodes in the tree.
private func strikethroughCount(_ node: borrowing MarkdownNode) -> Int {
    var n = 0
    if case .strikethrough = node.kind { n += 1 }
    node.children.forEach { child in
        n += strikethroughCount(child)
    }
    return n
}

/// cmark-gfm's strikethrough `match` (`extensions/strikethrough.c`) scans a `~` delimiter run into a
/// fixed `char buffer[101]` via `cmark_inline_parser_scan_delimiters(inline_parser, sizeof(buffer) - 1,
/// '~', …)` — so it reads AT MOST 100 consecutive `~` per delimiter token. A run of length N is chunked
/// into `floor(N/100)` length-100 tokens (never valid strikethrough delimiters — only lengths 1 and 2
/// are — so each stays literal text) plus one final token of length `N mod 100`. A strikethrough forms
/// when that final token is a valid delimiter (length 1 or 2) that pairs with a same-length opener, i.e.
/// for an opener of length L∈{1,2} and a later same-char run of length N, iff `N mod 100 == L`.
///
/// The CommonMark spec has NO such 100-cap: a run of length ≥ 3 is simply not a valid strikethrough
/// delimiter, so a length-101 run never pairs. This is a pure cmark fixed-buffer artifact.
///
/// This is a `[ref-b4b]` quirk: reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). The shipped deliverable (flag OFF) stays spec-correct — a strikethrough forms
/// only for a genuinely valid delimiter run (length 1 or 2) pairing with an equal-length opener, so
/// every `N ≥ 3` (including the `100·k + L` cases) stays literal. Ordinary short runs pair identically
/// under both flags.
@Suite("GFM strikethrough delimiter run-length 100-cap quirk")
struct StrikethroughRunLengthCapQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = [.strikethrough]
    private static let flagOn: MarkdownDocument.ParseOptions = [.strikethrough, .cmarkBugCompatibility]

    /// The concatenated inner text of the first `.strikethrough` node, or nil if none forms.
    private func strikeText(_ src: String, options: MarkdownDocument.ParseOptions) throws -> String? {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstStrikethroughText(doc.root)
        }
    }

    /// The number of `.strikethrough` nodes formed.
    private func strikeCount(_ src: String, options: MarkdownDocument.ParseOptions) throws -> Int {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Int in
            strikethroughCount(doc.root)
        }
    }

    // Inputs: an opener run of length L, then `)`, then a same-char run of length N. `**` (which never
    // closes) precedes the opener so the opener's before-char is punctuation and the opener flanks; the
    // `)` gives the strikethrough some non-tilde content so a formed node is unambiguous.
    private func input(openerLen: Int, tailCount: Int) -> String {
        "**" + String(repeating: "~", count: openerLen) + ")" + String(repeating: "~", count: tailCount)
    }

    // MARK: Flag ON — reproduce cmark's 100-cap chunking (forms iff N mod 100 == L)

    @Test("flag ON: L=1, N=101 forms (101 mod 100 == 1); content is `)` + 100 tildes")
    func flagOnL1N101() throws {
        let src = input(openerLen: 1, tailCount: 101)
        let content = try #require(try strikeText(src, options: Self.flagOn), "strikethrough must form")
        #expect(content == ")" + String(repeating: "~", count: 100))
        #expect(try strikeCount(src, options: Self.flagOn) == 1)
    }

    @Test("flag ON: L=1, N=201 forms (201 mod 100 == 1); content is `)` + 200 tildes")
    func flagOnL1N201() throws {
        let src = input(openerLen: 1, tailCount: 201)
        let content = try #require(try strikeText(src, options: Self.flagOn), "strikethrough must form")
        #expect(content == ")" + String(repeating: "~", count: 200))
        #expect(try strikeCount(src, options: Self.flagOn) == 1)
    }

    @Test("flag ON: L=2, N=102 forms (102 mod 100 == 2); content is `)` + 100 tildes")
    func flagOnL2N102() throws {
        let src = input(openerLen: 2, tailCount: 102)
        let content = try #require(try strikeText(src, options: Self.flagOn), "strikethrough must form")
        #expect(content == ")" + String(repeating: "~", count: 100))
        #expect(try strikeCount(src, options: Self.flagOn) == 1)
    }

    @Test("flag ON: the OPENER run is capped too (101-tilde opener → length-1 opener + closer)")
    func flagOnOpenerChunked() throws {
        // `**` + 101 `~` + `)` + `~`. The 101-tilde opener chunks into a length-100 literal token (not a
        // delimiter) + a final length-1 opener, which pairs with the trailing length-1 closer around `)`.
        let src = "**" + String(repeating: "~", count: 101) + ")~"
        let content = try #require(try strikeText(src, options: Self.flagOn), "strikethrough must form")
        #expect(content == ")")
        #expect(try strikeCount(src, options: Self.flagOn) == 1)
    }

    // Non-forming boundaries flag ON (N mod 100 != L): no strikethrough, all literal.

    @Test("flag ON: L=1, N=100 does NOT form (100 mod 100 == 0)")
    func flagOnL1N100() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 100), options: Self.flagOn) == nil)
    }

    @Test("flag ON: L=1, N=102 does NOT form (102 mod 100 == 2 != 1)")
    func flagOnL1N102() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 102), options: Self.flagOn) == nil)
    }

    @Test("flag ON: L=1, N=200 does NOT form (200 mod 100 == 0)")
    func flagOnL1N200() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 200), options: Self.flagOn) == nil)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (a length ≥ 3 run is never a delimiter)

    @Test("flag OFF: L=1, N=101 stays literal (no 100-cap in the spec)")
    func flagOffL1N101() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 101), options: Self.flagOff) == nil)
    }

    @Test("flag OFF: L=1, N=201 stays literal")
    func flagOffL1N201() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 201), options: Self.flagOff) == nil)
    }

    @Test("flag OFF: L=2, N=102 stays literal")
    func flagOffL2N102() throws {
        #expect(try strikeText(input(openerLen: 2, tailCount: 102), options: Self.flagOff) == nil)
    }

    @Test("flag OFF: the non-forming boundaries stay literal too")
    func flagOffBoundaries() throws {
        #expect(try strikeText(input(openerLen: 1, tailCount: 100), options: Self.flagOff) == nil)
        #expect(try strikeText(input(openerLen: 1, tailCount: 102), options: Self.flagOff) == nil)
        #expect(try strikeText(input(openerLen: 1, tailCount: 200), options: Self.flagOff) == nil)
    }

    // MARK: Ordinary controls — unchanged under BOTH flags

    @Test("controls: short runs pair (or not) identically under both flags")
    func ordinaryControls() throws {
        for options in [Self.flagOff, Self.flagOn] {
            // `~x~` and `~~x~~` form a strikethrough with content "x".
            #expect(try strikeText("~x~", options: options) == "x")
            #expect(try strikeCount("~x~", options: options) == 1)
            #expect(try strikeText("~~x~~", options: options) == "x")
            #expect(try strikeCount("~~x~~", options: options) == 1)
            // A length-3 run is not a valid delimiter, so `~~~x~~~` never forms.
            #expect(try strikeText("~~~x~~~", options: options) == nil)
            // The N=1 / N=2 base cases of the run-length family: the final token IS the whole run, so
            // `**~)~` (L=1, N=1) and `**~~)~~` (L=2, N=2) form with content "`)`".
            #expect(try strikeText("**~)~", options: options) == ")")
            #expect(try strikeCount("**~)~", options: options) == 1)
            #expect(try strikeText("**~~)~~", options: options) == ")")
            #expect(try strikeCount("**~~)~~", options: options) == 1)
        }
    }

    // MARK: doubleTilde composition — the cap only sets per-chunk length; the length gate still applies

    @Test("flag ON + doubleTilde: L=2/N=102 forms, but L=1/N=101 does NOT (single tilde rejected)")
    func flagOnDoubleTildeComposition() throws {
        // Under `.strikethroughDoubleTilde` only length-2 runs are valid delimiters. The 100-cap changes
        // only each chunk's length, so the final `N mod 100` token still has to be length 2 to pair:
        // L=2/N=102 forms (final token length 2), while L=1/N=101 (final token length 1) does not.
        let options: MarkdownDocument.ParseOptions = [.strikethrough, .strikethroughDoubleTilde, .cmarkBugCompatibility]
        let formed = try #require(
            try strikeText(input(openerLen: 2, tailCount: 102), options: options),
            "L=2/N=102 must form under doubleTilde")
        #expect(formed == ")" + String(repeating: "~", count: 100))
        #expect(try strikeText(input(openerLen: 1, tailCount: 101), options: options) == nil)
    }
}
