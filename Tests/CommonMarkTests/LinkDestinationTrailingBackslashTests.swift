/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A backslash before a line ending in a link destination is a literal backslash (Backslash escapes), and a link
/// destination cannot contain a line ending (Links), so the destination ends with that backslash. An even run of
/// trailing backslashes is a run of escaped backslashes.
@Suite("Link destination trailing backslash")
struct LinkDestinationTrailingBackslashTests {

    /// (destination url, title) of the first `.link` node in DFS order; nil fields if no link exists.
    private func firstLink(_ source: String) -> (url: String?, title: String?) {
        MarkdownDocument.withParsedDocument(source) { doc -> (String?, String?) in
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

    /// Top-level block kinds followed by the inline `(kind, literal)` list of the first block.
    private func blocksAndInlines(
        _ source: String
    ) -> (top: [MarkdownNode.Kind], inlines: [(kind: MarkdownNode.Kind, literal: String?)]) {
        MarkdownDocument.withParsedDocument(source) { doc in
            var top: [MarkdownNode.Kind] = []
            doc.root.children.forEach { top.append($0.kind) }
            return (top, paragraphInlines(doc))
        }
    }

    // MARK: - An odd run of trailing backslashes

    @Test("a link reference definition whose destination is one backslash ends at the line ending")
    func refDefBareTrailingBackslash() {
        // The destination is `\`, and the `]` line is a paragraph.
        let (top, inlines) = blocksAndInlines("[b]:\\\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("a link reference definition destination ending in a backslash after text ends at the line ending")
    func refDefTrailingBackslashAfterText() {
        let (top, inlines) = blocksAndInlines("[b]:a\\\nx")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["x"])
    }

    @Test("a link reference definition destination ending in a backslash after a path ends at the line ending")
    func refDefTrailingBackslashSlashPath() {
        let (top, inlines) = blocksAndInlines("[b]:/u\\\ny")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text])
        #expect(inlines.map(\.literal) == ["y"])
    }

    @Test("an inline link destination ending in a backslash forms no link, and the backslash is a hard line break")
    func inlineTrailingBackslash() {
        // After the destination `/u\` and the whitespace that follows it, `x)` is neither a link title nor `)` (Links),
        // so no link forms and the backslash before the line ending is a hard line break (Hard line breaks).
        let (top, inlines) = blocksAndInlines("[a](/u\\\nx)")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.kind) == [.text, .lineBreak, .text])
        #expect(inlines.map(\.literal) == ["[a](/u", nil, "x)"])
    }

    // MARK: - Other destinations

    @Test("a link reference definition destination ending in two backslashes ends in an escaped backslash")
    func refDefEvenTrailingBackslashes() {
        let (top, inlines) = blocksAndInlines("[b]:a\\\\\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("a backslash inside a link reference definition destination stays in the destination")
    func refDefBackslashMidDestination() {
        let (top, inlines) = blocksAndInlines("[b]:a\\b\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("a plain link reference definition destination ends at the line ending")
    func refDefPlainDestination() {
        let (top, inlines) = blocksAndInlines("[b]: x\n]")
        #expect(top == [.paragraph])
        #expect(inlines.map(\.literal) == ["]"])
    }

    @Test("a link reference definition whose destination is one backslash at the end of input is a definition")
    func refDefLoneTrailingBackslash() {
        let (top, _) = blocksAndInlines("[b]:\\")
        #expect(top == [])
    }

    @Test("inline link whose destination line ends in a backslash then a bare close paren")
    func inlineTrailingBackslashThenCloseParen() {
        // Whitespace, here a line ending, may separate the destination `/u\` from the `)` (Links).
        #expect(firstLink("[a](/u\\\n)").url == "/u\\")
    }
}
