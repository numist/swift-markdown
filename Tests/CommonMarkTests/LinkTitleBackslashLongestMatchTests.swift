/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A link title (Links) is the longest delimited match available: a `\` before the closing quote
/// escapes it only when a later quote can close the title; otherwise the `\` is a literal backslash
/// and that quote closes the title.
@Suite("Link title backslash longest match")
struct LinkTitleBackslashLongestMatchTests {

    /// The first `.link` node in DFS order: whether one exists, its url/title, and whether it has any
    /// inline children (link text).
    private func firstLink(
        _ source: String
    ) -> (found: Bool, url: String?, title: String?, hasText: Bool) {
        MarkdownDocument.withParsedDocument(source) { doc in
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
    ) -> (top: [MarkdownNode.Kind], inlines: [MarkdownNode.Kind]) {
        MarkdownDocument.withParsedDocument(source) { doc in
            var top: [MarkdownNode.Kind] = []
            doc.root.children.forEach { top.append($0.kind) }
            return (top, paragraphInlines(doc).map(\.kind))
        }
    }

    /// The destination ends at the line ending, which then separates it from the title `'\'`.
    @Test("empty-text link whose title backslash precedes the closing quote")
    func backslashBeforeCloseQuote() throws {
        let source = "[](a\n'\\')"
        let (top, inlines) = structure(source)
        #expect(top == [.paragraph])
        #expect(inlines == [.link])

        let link = firstLink(source)
        try #require(link.found)
        #expect(link.url == "a")
        #expect(link.title == "\\")
        #expect(!link.hasText)
    }

    @Test("plain single-char destination")
    func plainDestination() throws {
        let link = firstLink("[](a)")
        try #require(link.found)
        #expect(link.url == "a")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    @Test("balanced parenthesized destination")
    func balancedParenDestination() throws {
        let link = firstLink("[]((a))")
        try #require(link.found)
        #expect(link.url == "(a)")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    /// A bare destination includes parentheses only when they are escaped or balanced (Links).
    @Test("unbalanced open paren destination stopped by a space is no link")
    func openParenDestinationStoppedBySpace() throws {
        let link = firstLink("[](( )")
        #expect(!link.found)
    }

    /// Whitespace, including a line ending, may precede the destination, which is then empty.
    @Test("empty destination across a line ending")
    func emptyDestinationAcrossLineEnding() throws {
        let link = firstLink("[](\n)")
        try #require(link.found)
        #expect(link.url == "")
        #expect(link.title == "")
        #expect(!link.hasText)
    }

    /// A later quote can close the title, so the `\'` is a backslash escape.
    @Test("escaped closing quote extends the title to a later quote")
    func escapedCloseQuoteExtendsTitle() throws {
        let link = firstLink("[](a '\\'')")
        try #require(link.found)
        #expect(link.url == "a")
        #expect(link.title == "'")
        #expect(!link.hasText)
    }
}
