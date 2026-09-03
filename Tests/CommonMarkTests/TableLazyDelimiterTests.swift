/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A GFM table delimiter row that arrives as a LAZY continuation must not open a table. cmark opens a
/// table only while processing the delimiter line as a normal (container-prefix-matched) line
/// (`try_opening_table_block` runs from the block-start machinery, which a lazy continuation bypasses).
/// So `>o` / `--` (the `--` lazily continues the block-quote paragraph, with no `>`) is a paragraph in
/// cmark, not a table. When the delimiter line carries the block-quote prefix (`>o` / `>|-`), the table
/// forms normally. The rewrite detects tables at finalize and previously couldn't see the laziness, so
/// it wrongly formed a table. Spec-aligned `[fix]`, asserted WITHOUT `.cmarkBugCompatibility`.
@Suite("Table lazy-continuation delimiter row")
struct TableLazyDelimiterTests {

    private func nodeKinds(_ source: String) throws -> (hasTable: Bool, hasHeading: Bool, hasParagraph: Bool) {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> (Bool, Bool, Bool) in
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

    // MARK: - FIX: a lazy-continuation delimiter row does NOT form a table

    @Test("lazy `--` continuation in a block quote stays a paragraph")
    func lazyDashDash() throws {
        let k = try nodeKinds(">o\n--")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy pipe delimiter continuation in a block quote stays a paragraph")
    func lazyPipeDelim() throws {
        let k = try nodeKinds(">o\n|-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy colon delimiter continuation in a block quote stays a paragraph")
    func lazyColonDelim() throws {
        let k = try nodeKinds(">o\n:-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    @Test("lazy pipe delimiter continuation in a LIST ITEM stays a paragraph")
    func lazyPipeDelimInList() throws {
        // The signal is container-agnostic (`!allMatched`): a list-item lazy continuation (the `|-` is
        // not indented to the item's content column) is not a delimiter row either. cmark: list › paragraph.
        let k = try nodeKinds("- o\n|-")
        #expect(!k.hasTable && k.hasParagraph)
    }

    // MARK: - LEAVE: prefixed continuation and plain paragraphs still form tables / setext

    @Test("a prefixed pipe delimiter in a block quote still forms a table")
    func prefixedPipeFormsTable() throws {
        let k = try nodeKinds(">o\n>|-")
        #expect(k.hasTable)
    }

    @Test("a prefixed `--` in a block quote is still a setext heading")
    func prefixedDashDashIsHeading() throws {
        let k = try nodeKinds(">o\n>--")
        #expect(k.hasHeading && !k.hasTable)
    }

    @Test("a plain (non-quoted) pipe delimiter still forms a table")
    func plainPipeFormsTable() throws {
        let k = try nodeKinds("o\n|-")
        #expect(k.hasTable)
    }

    @Test("a plain `--` is still a setext heading")
    func plainDashDashIsHeading() throws {
        let k = try nodeKinds("o\n--")
        #expect(k.hasHeading && !k.hasTable)
    }
}
