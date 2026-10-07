/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A delimiter row turns the open paragraph into a table before any link reference definition is
/// extracted from it (Tables (extension), Link reference definitions), so text shaped like a link
/// reference definition becomes table content.
@Suite("GFM table vs link reference definition precedence")
struct TableVsReferenceDefinitionTests {

    private struct Block {
        enum Kind { case none, paragraph, heading, table, other }
        var kind: Kind = .none
        var alignments: [MarkdownNode.TableAlignment] = []
        var headerCells: [String] = []
        var bodyRows: [[String]] = []
        /// The concatenated literal text of the block's direct-child inlines (paragraph / heading; empty for a table / other).
        var text: String = ""
    }

    /// Extract a `.table` node's header-cell texts, per-column alignments, and body-row cell texts.
    private func tableBlock(from node: borrowing MarkdownNode) -> Block {
        var block = Block()
        block.kind = .table
        node.children.forEach { row in
            guard case .tableRow(let isHeader) = row.kind else { return }
            var cellTexts: [String] = []
            var aligns: [MarkdownNode.TableAlignment] = []
            row.children.forEach { cell in
                guard case .tableCell(let alignment, _, _) = cell.kind else { return }
                aligns.append(alignment)
                var text = ""
                cell.children.forEach { inline in
                    if let lit = inline.literal() { text += lit }
                }
                cellTexts.append(text)
            }
            if isHeader {
                block.headerCells = cellTexts
                block.alignments = aligns
            } else {
                block.bodyRows.append(cellTexts)
            }
        }
        return block
    }

    /// The document's top-level blocks, each classified as paragraph / heading / table (with shape).
    private func blocks(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) -> [Block] {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> [Block] in
            var out: [Block] = []
            doc.root.children.forEach { child in
                var block = Block()
                switch child.kind {
                case .paragraph:
                    block.kind = .paragraph
                    child.children.forEach { inline in
                        if let lit = inline.literal() { block.text += lit }
                    }
                case .heading:
                    block.kind = .heading
                    child.children.forEach { inline in
                        if let lit = inline.literal() { block.text += lit }
                    }
                case .table:
                    block = self.tableBlock(from: child)
                default:
                    block.kind = .other
                }
                out.append(block)
            }
            return out
        }
    }

    /// The first resolved reference-link URL anywhere in `source`, or `nil`.
    private func firstLinkURL(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) -> String? {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> String? in
            var found: String? = nil
            func walk(_ n: borrowing MarkdownNode) {
                if found == nil, case .link = n.kind { found = n.url() }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return found
        }
    }

    @Test("a delimiter-row second line forms a table even when the paragraph reads as a link reference definition")
    func delimiterRowBeatsReferenceDefinition() throws {
        // Read as a whole, `[\n|-\n]:/` is a link reference definition with label `\n|-\n`.
        let doc = blocks("[\n|-\n]:/")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.alignments == [.none])
        #expect(table.headerCells == ["["])
        #expect(table.bodyRows == [["]:/"]])
        #expect(doc.count == 1)
    }

    @Test("the same table forms when the paragraph does not read as a link reference definition")
    func delimiterRowWithoutColon() throws {
        let doc = blocks("[\n|-\n]a")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.alignments == [.none])
        #expect(table.headerCells == ["["])
        #expect(table.bodyRows == [["]a"]])
        #expect(doc.count == 1)
    }

    @Test("a complete first-line link reference definition becomes the header cell when a delimiter row follows")
    func firstLineReferenceDefinitionAbsorbedAsHeader() throws {
        let doc = blocks("[foo]: /bar\n|-\n|x")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.headerCells == ["[foo]: /bar"])
        #expect(table.bodyRows == [["x"]])
        #expect(doc.count == 1)
        // No definition exists, so a later `[foo]` stays literal.
        #expect(firstLinkURL("[foo]: /bar\n|-\n|x\n\n[foo]") == nil, "the link reference definition must not be registered")
    }

    @Test("a multi-line link reference definition without a delimiter row defines a link")
    func multiLineReferenceDefinition() throws {
        let doc = blocks("[a\nb]: /u\n\n[a b]")
        try #require(doc.count == 1, "expected the link reference definition to be consumed, leaving one block; got \(doc.count)")
        #expect(doc[0].kind == .paragraph, "expected a paragraph, got \(doc[0].kind)")
        let url = try #require(firstLinkURL("[a\nb]: /u\n\n[a b]"), "expected `[a b]` to resolve to a link")
        #expect(url == "/u")
    }

    // MARK: - Delimiter row after a complete link reference definition

    /// The definition's paragraph is open when the bare `-` is read, and an empty list item cannot interrupt a
    /// paragraph (List items), so the `-` is paragraph text once the definition is removed.
    @Test("a bare `-` after a complete single-line link reference definition is paragraph text")
    func bareDelimiterAfterCompleteReferenceDefinition() {
        #expect(TreeDump.dump("[o]:o\n-", options: [.tables]) == """
            document
              paragraph
                text "-"

            """)
    }

    /// The definition's paragraph is open when the bare `-` is read, and an empty list item cannot interrupt a
    /// paragraph (List items), so the `-` is paragraph text once the definition is removed.
    @Test("a bare `-` after a link reference definition with a space before the destination is paragraph text")
    func bareDelimiterAfterCompleteReferenceDefinitionWithSpace() {
        #expect(TreeDump.dump("[o]: o\n-", options: [.tables]) == """
            document
              paragraph
                text "-"

            """)
    }

    @Test("a pipe delimiter row after a complete link reference definition forms a table")
    func pipeDelimiterAfterCompleteReferenceDefinitionFormsTable() throws {
        let doc = blocks("[o]:o\n|-")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.headerCells == ["[o]:o"])
        #expect(table.bodyRows == [])
        #expect(doc.count == 1)
    }
}
