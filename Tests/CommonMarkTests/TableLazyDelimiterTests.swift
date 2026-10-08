/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A delimiter row on a lazy continuation line (Block quotes, List items) is paragraph text, just as a
/// lazy `--` is not a setext heading underline, so no table forms.
@Suite("Table delimiter row on a lazy continuation line")
struct TableLazyDelimiterTests {

    private func nodeKinds(_ source: String) -> (hasTable: Bool, hasHeading: Bool, hasParagraph: Bool) {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> (Bool, Bool, Bool) in
            var hasTable = false, hasHeading = false, hasParagraph = false
            func walk(_ n: borrowing MarkdownNode) {
                switch n.kind {
                case .table: hasTable = true
                case .heading: hasHeading = true
                case .paragraph: hasParagraph = true
                default: break
                }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (hasTable, hasHeading, hasParagraph)
        }
    }

    // MARK: - Lazy continuation lines

    @Test("lazy `--` continuation in a block quote is paragraph text")
    func lazyDashDash() {
        let k = nodeKinds(">o\n--")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy pipe delimiter continuation in a block quote is paragraph text")
    func lazyPipeDelim() {
        let k = nodeKinds(">o\n|-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy colon delimiter continuation in a block quote is paragraph text")
    func lazyColonDelim() {
        let k = nodeKinds(">o\n:-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy pipe delimiter continuation in a list item is paragraph text")
    func lazyPipeDelimInList() {
        let k = nodeKinds("- o\n|-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    // MARK: - Prefixed and top-level lines

    @Test("a prefixed pipe delimiter in a block quote forms a table")
    func prefixedPipeFormsTable() {
        let k = nodeKinds(">o\n>|-")
        #expect(k.hasTable)
    }

    @Test("a prefixed `--` in a block quote is a setext heading underline")
    func prefixedDashDashIsHeading() {
        let k = nodeKinds(">o\n>--")
        #expect(k.hasHeading && !k.hasTable)
    }

    @Test("a top-level pipe delimiter forms a table")
    func plainPipeFormsTable() {
        let k = nodeKinds("o\n|-")
        #expect(k.hasTable)
    }

    @Test("a top-level `--` is a setext heading underline")
    func plainDashDashIsHeading() {
        let k = nodeKinds("o\n--")
        #expect(k.hasHeading && !k.hasTable)
    }
}
