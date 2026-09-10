/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark's link-title scanner (`scan_link_title`, re2c `['] (escaped_char|[^'\x00])* [']` plus the
/// `"…"` and `(…)` forms in `src/scanners.re`) is a *longest-match* DFA. At a `\` it keeps both
/// readings alive at once — the byte as the start of an `escaped_char` (backslash + ASCII
/// punctuation) AND the byte as an ordinary body byte (`[^'\x00]` includes `\`) — and closes on the
/// furthest reachable delimiter. An eager left-to-right "always escape `\X`" scan diverges when a `\`
/// precedes the closing delimiter and there is no later delimiter to escape onto: cmark reads the `\`
/// as a body byte and closes on the following delimiter, where the eager scan consumes the delimiter
/// and never finds a close.
///
/// Reproduces a differential-fuzzer finding. Input `[]((` + newline + `'\')`:
/// - the destination scan stops at the `(` before the newline (a newline is terminating whitespace in
///   a bare destination), giving destination `(`;
/// - the spacechars between destination and title skip the newline;
/// - the title `'\'` closes on the *second* quote (the `\` is body, not an escape), interior `\`.
///
/// So cmark forms an inline link with empty text, destination `(`, and title `\`. The eager scan
/// never matched the title, so the whole `[]((` stayed literal text split by a soft break.
@Suite("Link title backslash longest match")
struct LinkTitleBackslashLongestMatchTests {

    /// The first `.link` node in DFS order: whether one exists, its url/title, and whether it has any
    /// inline children (link text).
    private func firstLink(
        _ source: String
    ) throws -> (found: Bool, url: String?, title: String?, hasText: Bool) {
        try MarkdownDocument.withParsedDocument(source) { doc in
            var found = false
            var url: String? = nil
            var title: String? = nil
            var hasText = false
            func walk(_ node: borrowing MarkdownNode) {
                if node.kind == .link, !found {
                    found = true
                    url = node.url()
                    title = node.title()
                    var count = 0
                    node.children.forEach { _ in count += 1 }
                    hasText = count > 0
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (found, url, title, hasText)
        }
    }

    /// Top-level block kinds followed by the first paragraph's inline kinds.
    private func structure(
        _ source: String
    ) throws -> (top: [MarkdownNode.Kind], inlines: [MarkdownNode.Kind]) {
        try MarkdownDocument.withParsedDocument(source) { doc in
            var top: [MarkdownNode.Kind] = []
            doc.root.children.forEach { top.append($0.kind) }
            return (top, paragraphInlines(doc).map(\.kind))
        }
    }

    // MARK: - FIX: the finding

    @Test("empty-text link whose title backslash precedes the closing quote")
    func findingBackslashBeforeCloseQuote() throws {
        let source = "[]((\n'\\')"
        let (top, inlines) = try structure(source)
        #expect(top == [.paragraph])
        // Fixture sanity: the whole construct collapses to a single inline link (not the buggy
        // text / soft-break / text split).
        #expect(inlines == [.link])

        let link = try firstLink(source)
        try #require(link.found)  // fixture sanity: a link must exist
        #expect(link.url == "(")
        #expect(link.title == "\\")
        #expect(!link.hasText)
    }

    // MARK: - GUARD: currently-matching cases stay matching

    @Test("plain single-char destination")
    func plainDestination() throws {
        let link = try firstLink("[](a)")
        try #require(link.found)
        #expect(link.url == "a")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    @Test("balanced parenthesized destination")
    func balancedParenDestination() throws {
        let link = try firstLink("[]((a))")
        try #require(link.found)
        #expect(link.url == "(a)")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    @Test("open paren destination stopped by a space")
    func openParenDestinationStoppedBySpace() throws {
        // `[](( )`: the destination scan stops at the space (`(`), the spacechars skip it, and the `)`
        // closes the link — destination `(`, no title.
        let link = try firstLink("[](( )")
        try #require(link.found)
        #expect(link.url == "(")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    @Test("empty destination across a newline")
    func emptyDestinationAcrossNewline() throws {
        // `[](` + newline + `)`: the newline is skipped as spacechars before the destination scan, so
        // the destination is empty and the `)` closes the link.
        let link = try firstLink("[](\n)")
        try #require(link.found)
        #expect(link.url == "")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    @Test("escaped closing quote extends the title to a later quote")
    func escapedCloseQuoteExtendsTitle() throws {
        // `[](a '\'')`: the `\'` escapes the first inner quote, so the title `'\''` closes on the
        // LAST quote (interior `\'` → `'`). This is the case where escaping DOES yield the longest
        // match, and must keep working.
        let link = try firstLink("[](a '\\'')")
        try #require(link.found)
        #expect(link.url == "a")
        #expect(link.title == "'")
        #expect(!link.hasText)
    }
}
