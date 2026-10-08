/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An indented dump of a parsed document's node kinds and text, so assertions cover the whole nested
/// tree.
fileprivate func dumpTree(_ source: String, options: MarkdownDocument.ParseOptions = [.tables]) -> String {
    MarkdownDocument.withParsedDocument(source, options: options) { doc -> String in
        var out = ""
        func label(_ n: borrowing MarkdownNode) -> String {
            switch n.kind {
            case .document: return "Document"
            case .blockQuote: return "BlockQuote"
            case .list: return "List"
            case .item: return "Item"
            case .paragraph: return "Paragraph"
            case .heading(let level): return "Heading(\(level))"
            case .table: return "Table"
            case .tableRow(let isHeader): return isHeader ? "Head" : "Body"
            case .tableCell: return "Cell"
            case .text: return "Text " + (n.literal().map { "\"\($0)\"" } ?? "")
            case .softBreak: return "SoftBreak"
            case .lineBreak: return "LineBreak"
            default: return "\(n.kind)"
            }
        }
        func walk(_ n: borrowing MarkdownNode, depth: Int) {
            out += String(repeating: "  ", count: depth) + label(n) + "\n"
            n.children.forEach { walk($0, depth: depth + 1) }
        }
        walk(doc.root, depth: 0)
        return out
    }
}

/// When a delimiter row follows a paragraph of several lines, the paragraph's last line is the header
/// row and the earlier lines remain a paragraph (Tables (extension)). These cases place the paragraph in
/// a block quote or list item, join its lines with CRLF line endings, or indent its lines.
@Suite("Table takes the last line of a nested or indented paragraph as its header row")
struct TablePrecedingParagraphNoncontiguousTests {

    // MARK: - Earlier lines remain a paragraph

    @Test("nested block quote: preceding line splits off, header is the last line")
    func nestedBlockQuote() {
        #expect(dumpTree("> x\n> a\n> |-") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
            Table
              Head
                Cell
                  Text "a"

        """)
    }

    @Test("nested list item: preceding line splits off, header is the last line")
    func nestedListItem() {
        #expect(dumpTree("- x\n  a\n  |-") == """
        Document
          List
            Item
              Paragraph
                Text "x"
              Table
                Head
                  Cell
                    Text "a"

        """)
    }

    @Test("CRLF line endings: preceding line splits off, header is the last line")
    func crlfLineEndings() {
        #expect(dumpTree("x\r\na\r\n|-") == """
        Document
          Paragraph
            Text "x"
          Table
            Head
              Cell
                Text "a"

        """)
    }

    @Test("nested block quote: a following body row joins the table")
    func nestedBlockQuoteBodyRow() {
        #expect(dumpTree("> x\n> a\n> |-\n> b") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
            Table
              Head
                Cell
                  Text "a"
              Body
                Cell
                  Text "b"

        """)
    }

    @Test("CRLF: a following body row joins the table")
    func crlfBodyRow() {
        #expect(dumpTree("x\r\na\r\n|-\r\nb") == """
        Document
          Paragraph
            Text "x"
          Table
            Head
              Cell
                Text "a"
            Body
              Cell
                Text "b"

        """)
    }

    // MARK: - No earlier lines

    @Test("bare block-quote header: no preceding paragraph")
    func bareNestedBlockQuoteTable() {
        #expect(dumpTree("> a\n> |-") == """
        Document
          BlockQuote
            Table
              Head
                Cell
                  Text "a"

        """)
    }

    @Test("bare list-item header: no preceding paragraph")
    func bareNestedListTable() {
        #expect(dumpTree("- a\n  |-") == """
        Document
          List
            Item
              Table
                Head
                  Cell
                    Text "a"

        """)
    }

    // MARK: - No table

    @Test("lazy block-quote continuation: the delimiter is lazy, so no table and no split")
    func lazyBlockQuoteNoSplit() {
        // A delimiter row on a lazy continuation line is paragraph text (Block quotes).
        #expect(dumpTree("> x\na\n|-") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
              SoftBreak
              Text "a"
              SoftBreak
              Text "|-"

        """)
    }

    @Test("a nested header row whose cell count differs from the delimiter row's forms no table")
    func nestedHeaderMismatchStaysParagraph() {
        #expect(dumpTree("> x\n> a|b\n> |-") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
              SoftBreak
              Text "a|b"
              SoftBreak
              Text "|-"

        """)
    }

    // MARK: - Top-level paragraph

    @Test("contiguous: multiple preceding lines split off as one paragraph")
    func contiguousMultiPreceding() {
        #expect(dumpTree("x\ny\na\n|-") == """
        Document
          Paragraph
            Text "x"
            SoftBreak
            Text "y"
          Table
            Head
              Cell
                Text "a"

        """)
    }

    // MARK: - Source ranges

    @Test("CRLF split nodes carry valid source ranges")
    func crlfSplitNodesHaveValidRanges() {
        // Soft and hard line breaks have no source range (see SourceRangeCompletenessTests).
        let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]
        let nodes = MarkdownDocument.withParsedDocument("x\r\na\r\n|-\r\nb", options: options) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] in
            var out: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            dfsCompleteness(doc.root, into: &out)
            return out
        }
        for node in nodes {
            switch node.kind {
            case .softBreak, .lineBreak:
                continue
            default:
                break
            }
            #expect(node.range != nil, "missing source range on \(node.kind)")
            if let range = node.range {
                #expect(range.lowerBound <= range.upperBound, "inverted range on \(node.kind)")
            }
        }
    }

    // MARK: - Tab after the block quote marker

    @Test("a tab after the block quote marker splits the same with and without source positions")
    func tabAfterBlockQuoteMarkerSplit() {
        let expected = """
        Document
          BlockQuote
            Paragraph
              Text "x"
            Table
              Head
                Cell
                  Text "y"

        """
        #expect(dumpTree(">\tx\n> y\n> |-", options: [.tables]) == expected)
        #expect(dumpTree(">\tx\n> y\n> |-", options: [.tables, .sourcePosition]) == expected)
    }

    // MARK: - Only the delimiter row's own line decides whether a table opens

    /// An indented paragraph continuation line is paragraph text (Paragraphs) and becomes the header row;
    /// only an indented delimiter row would prevent the table.
    @Test("an indented header row line does not prevent the table")
    func indentedEarlierLineFormsTable() {
        let expected = """
        Document
          Paragraph
            Text "x"
          Table
            Head
              Cell
                Text "a"

        """
        #expect(dumpTree("x\n    a\n|-") == expected)
        // The same, indented four columns within a block quote.
        #expect(dumpTree("> x\n>     a\n> |-") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
            Table
              Head
                Cell
                  Text "a"

        """)
    }

    @Test("a header row on a lazy continuation line forms a table when the delimiter row is prefixed")
    func lazyEarlierLineFormsTable() {
        #expect(dumpTree("> x\ny\n> |-") == """
        Document
          BlockQuote
            Paragraph
              Text "x"
            Table
              Head
                Cell
                  Text "y"

        """)
    }
}

