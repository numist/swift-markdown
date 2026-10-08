/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The parser strips spaces, tabs and line endings from both ends of a link destination, in an inline link and in a
/// link reference definition, and keeps whitespace inside it. A link title keeps all its whitespace.
@Suite("Link destination whitespace trimming")
struct LinkDestinationTrimTests {

    /// (destination url, title) of the first `.link` node in DFS order; nil fields if no link exists.
    private func firstLink(
        _ source: String, options: MarkdownDocument.ParseOptions = []
    ) -> (url: String?, title: String?) {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> (String?, String?) in
            var found = false
            var url: String? = nil
            var title: String? = nil
            func walk(_ node: borrowing MarkdownNode) {
                if node.kind == .link, !found {
                    found = true
                    url = node.url()
                    title = node.title()
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (url, title)
        }
    }

    // MARK: - Inline link destinations

    @Test("all-whitespace angle destination trims to empty (single space)")
    func inlineAllWhitespaceSingle() {
        #expect(firstLink("[](< >)").url == "")
    }

    @Test("all-whitespace angle destination trims to empty (two spaces)")
    func inlineAllWhitespaceDouble() {
        #expect(firstLink("[](<  >)").url == "")
    }

    @Test("leading whitespace is trimmed")
    func inlineLeadingTrimmed() {
        #expect(firstLink("[](< a>)").url == "a")
    }

    @Test("trailing whitespace is trimmed")
    func inlineTrailingTrimmed() {
        #expect(firstLink("[](<a >)").url == "a")
    }

    @Test("leading whitespace is trimmed and the backslash escape resolves")
    func inlineLeadingTrimAndUnescape() {
        #expect(firstLink("[](< \\!a>)").url == "!a")
    }

    // MARK: - Link reference definition destinations

    @Test("link reference definition leading whitespace is trimmed")
    func refDefLeadingTrimmed() {
        #expect(firstLink("[x]: < a>\n\n[x]").url == "a")
    }

    @Test("link reference definition all-whitespace destination trims to empty")
    func refDefAllWhitespace() {
        #expect(firstLink("[x]: < >\n\n[x]").url == "")
    }

    // MARK: - Interior whitespace

    @Test("interior whitespace in an inline destination is kept")
    func inlineInteriorKept() {
        #expect(firstLink("[](<a b>)").url == "a b")
    }

    @Test("interior whitespace in a link reference definition destination is kept")
    func refDefInteriorKept() {
        #expect(firstLink("[x]: <a b>\n\n[x]").url == "a b")
    }

    // MARK: - Backslash escapes

    @Test("a backslash escape in an angle destination resolves")
    func angleEscapeRemoval() {
        #expect(firstLink("[](<a\\>b>)").url == "a>b")
    }

    @Test("a backslash escape in a bare destination resolves")
    func bareEscapeRemoval() {
        #expect(firstLink("[](a\\)b)").url == "a)b")
    }

    // MARK: - Link titles

    @Test("a title with no surrounding space is kept as is")
    func titleNoSpaceUnaffected() {
        let link = firstLink("[](<a> \"t\")")
        #expect(link.url == "a")
        #expect(link.title == "t")
    }

    @Test("whitespace at the ends of a title is kept")
    func titleSurroundingSpacePreserved() {
        let link = firstLink("[](<a> \" t \")")
        #expect(link.url == "a")
        #expect(link.title == " t ")
    }
}
