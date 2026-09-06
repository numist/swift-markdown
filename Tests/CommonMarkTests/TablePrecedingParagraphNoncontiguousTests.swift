/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A compact, indented structural dump of a parsed document (kinds + literal text + table shape). Used
/// to assert the full nested tree, since these cases live inside block quotes / list items where a
/// top-level-only block classifier can't see the split.
fileprivate func dumpTree(_ source: String, options: MarkdownDocument.ParseOptions = [.tables]) throws -> String {
    try MarkdownDocument.withParsedDocument(source, options: options) { doc -> String in
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

/// A GFM table delimiter row can interrupt an open paragraph, taking the paragraph's LAST line as the
/// header and splitting the earlier lines off into a preceding paragraph (cmark's
/// `try_inserting_table_header_paragraph`). Commit 4adf7f9 implemented this for the source-CONTIGUOUS
/// paragraph representation. These cover the NON-contiguous representations — a paragraph accumulated as
/// a zero-copy segment list (nested block-quote / list continuations, and CRLF-joined lines) — where the
/// header and the preceding lines must be reconstructed from the stored segments rather than a single
/// source range.
///
/// Parsed with `.tables` but WITHOUT `.cmarkBugCompatibility`: a table interrupting a paragraph is
/// spec-aligned, so this is an unconditional structural `[fix]`.
@Suite("GFM table interrupts a non-contiguous paragraph, taking its last line as header")
struct TablePrecedingParagraphNoncontiguousTests {

    // MARK: - FIX: the split now works for non-contiguous paragraph representations

    @Test("nested block quote: preceding line splits off, header is the last line")
    func nestedBlockQuote() throws {
        // `> x\n> a\n> |-` : inside the block quote, `x` becomes a paragraph and `a`+`|-` a table.
        #expect(try dumpTree("> x\n> a\n> |-") == """
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
    func nestedListItem() throws {
        // `- x\n  a\n  |-` : inside the list item, `x` becomes a paragraph and `a`+`|-` a table.
        #expect(try dumpTree("- x\n  a\n  |-") == """
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
    func crlfLineEndings() throws {
        // `x\r\na\r\n|-` : CRLF joins accumulate as a non-contiguous segment list; the split is the same.
        #expect(try dumpTree("x\r\na\r\n|-") == """
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
    func nestedBlockQuoteBodyRow() throws {
        #expect(try dumpTree("> x\n> a\n> |-\n> b") == """
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
    func crlfBodyRow() throws {
        #expect(try dumpTree("x\r\na\r\n|-\r\nb") == """
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

    // MARK: - GUARD: bare 2-line nested headers keep working (no preceding paragraph)

    @Test("bare block-quote header: no preceding paragraph")
    func bareNestedBlockQuoteTable() throws {
        #expect(try dumpTree("> a\n> |-") == """
        Document
          BlockQuote
            Table
              Head
                Cell
                  Text "a"

        """)
    }

    @Test("bare list-item header: no preceding paragraph")
    func bareNestedListTable() throws {
        #expect(try dumpTree("- a\n  |-") == """
        Document
          List
            Item
              Table
                Head
                  Cell
                    Text "a"

        """)
    }

    // MARK: - GUARD: cases that must NOT split

    @Test("lazy block-quote continuation: the delimiter is lazy, so no table and no split")
    func lazyBlockQuoteNoSplit() throws {
        // `> x\na\n|-` : `a` and `|-` are lazy continuations (no `>`). cmark opens table blocks against
        // an ancestor on a lazy line, so `try_opening_table_block` never sees a paragraph parent — no
        // table opens, and the whole thing stays one lazy block-quote paragraph.
        #expect(try dumpTree("> x\na\n|-") == """
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

    @Test("nested header column mismatch poisons the paragraph (no table)")
    func nestedHeaderMismatchStaysParagraph() throws {
        // `> x\n> a|b\n> |-` : header `a|b` has two cells but the delimiter one column — a mismatch, so
        // cmark marks the paragraph never-a-table (TABLE_VISITED). It stays one paragraph.
        #expect(try dumpTree("> x\n> a|b\n> |-") == """
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

    // MARK: - GUARD: the contiguous split (4adf7f9) still works

    @Test("contiguous: multiple preceding lines split off as one paragraph")
    func contiguousMultiPreceding() throws {
        #expect(try dumpTree("x\ny\na\n|-") == """
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

    // MARK: - Positions: the top-level CRLF split carries valid (present, non-inverted) source ranges

    @Test("CRLF split nodes carry valid source ranges")
    func crlfSplitNodesHaveValidRanges() throws {
        // The top-level CRLF split is fully position-stamped (the table's rows/cells map back through
        // the flattened segment run map). Assert every node carries a present, non-inverted range —
        // breaks are legitimately position-less (see SourceRangeCompletenessTests).
        let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]
        let nodes = try MarkdownDocument.withParsedDocument("x\r\na\r\n|-\r\nb", options: options) {
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
            #expect(node.range != nil, "unstamped \(node.kind)")
            if let range = node.range {
                #expect(range.lowerBound <= range.upperBound, "inverted range on \(node.kind)")
            }
        }
    }

    // MARK: - Materialized representation: a tab-expanded first line splits the same way

    @Test("tab-prefixed lines split identically whether positions are on or off")
    func materializedTabPrefixSplit() throws {
        // `>\tx\n> y\n> |-` : the block-quote marker's tab makes the paragraph's first line tab-expanded.
        // With positions OFF the paragraph accumulates as a materialized byte buffer; with positions ON it
        // accumulates as a source-mapped segment list. The split must reconstruct the same structure from
        // either representation — `x` splits off, `y`+`|-` forms the table.
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
        #expect(try dumpTree(">\tx\n> y\n> |-", options: [.tables]) == expected)                    // materialized
        #expect(try dumpTree(">\tx\n> y\n> |-", options: [.tables, .sourcePosition]) == expected)    // segments
    }

    // MARK: - The delimiter, not the original second line, gates the table after a multi-line split

    @Test("an indented earlier line does not veto the split table")
    func indentedEarlierLineStillFormsTable() throws {
        // `x\n    a\n|-` : the second physical line `    a` is indented 4 columns (stripped, so the
        // paragraph is a non-contiguous segment list), but the DELIMITER line `|-` is unindented. cmark
        // gates the table on the delimiter line's indent (`try_opening_table_block`'s `!indented`), so the
        // table forms. The finalize gate must therefore reflect the delimiter, not the earlier line.
        let expected = """
        Document
          Paragraph
            Text "x"
          Table
            Head
              Cell
                Text "a"

        """
        #expect(try dumpTree("x\n    a\n|-") == expected)
        // Nested: the same, inside a block quote (matched continuation indented 4 within the quote).
        #expect(try dumpTree("> x\n>     a\n> |-") == """
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

    @Test("a lazy earlier line does not veto the split table when the delimiter is matched")
    func lazyEarlierLineStillFormsTable() throws {
        // `> x\ny\n> |-` : the second line `y` is a LAZY block-quote continuation, but the delimiter line
        // `> |-` is a MATCHED (non-lazy) continuation. cmark opens the table on the matched delimiter line,
        // so `x` splits off and `y`+`|-` forms the table. (Contrast `> x\na\n|-`, where the delimiter ITSELF
        // is lazy and no table opens.)
        #expect(try dumpTree("> x\ny\n> |-") == """
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

