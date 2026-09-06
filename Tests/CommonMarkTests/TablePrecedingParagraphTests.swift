/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A GFM table delimiter row can interrupt an open paragraph, taking the paragraph's LAST line as the
/// header. cmark-gfm opens the table WHILE processing the delimiter line (`try_opening_table_header`);
/// its `row_from_string` treats every newline-terminated segment of the accumulated paragraph as a
/// preceding-paragraph offset and resets, so the effective header is the line IMMEDIATELY before the
/// delimiter, and everything before it splits off into a separate paragraph
/// (`try_inserting_table_header_paragraph`).
///
/// The rewrite detected tables only when the delimiter was a paragraph's SECOND physical line, so a
/// header preceded by earlier paragraph text (`x\na\n|-`) stayed one paragraph. These assert the split.
/// Parsed with `.tables` but WITHOUT `.cmarkBugCompatibility`: this is a spec-aligned structural `[fix]`.
@Suite("GFM table delimiter interrupts a paragraph, taking its last line as header")
struct TablePrecedingParagraphTests {

    private enum Block: Equatable {
        case paragraph(String)
        case heading(String)
        case table(header: [String], body: [[String]])
        case other
    }

    /// The top-level block sequence of `source`, each classified as a paragraph/heading/table.
    private func blocks(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) throws -> [Block] {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> [Block] in
            func inlineText(_ node: borrowing MarkdownNode) -> String {
                var text = ""
                func walk(_ n: borrowing MarkdownNode) {
                    if let lit = n.literal() { text += lit }
                    n.children.forEach { walk($0) }
                }
                node.children.forEach { walk($0) }
                return text
            }
            var result: [Block] = []
            doc.root.children.forEach { child in
                switch child.kind {
                case .paragraph:
                    result.append(.paragraph(inlineText(child)))
                case .heading:
                    result.append(.heading(inlineText(child)))
                case .table:
                    var header: [String] = []
                    var body: [[String]] = []
                    child.children.forEach { row in
                        guard case .tableRow(let isHeader) = row.kind else { return }
                        var cells: [String] = []
                        row.children.forEach { cell in
                            guard case .tableCell = cell.kind else { return }
                            cells.append(inlineText(cell))
                        }
                        if isHeader { header = cells } else { body.append(cells) }
                    }
                    result.append(.table(header: header, body: body))
                default:
                    result.append(.other)
                }
            }
            return result
        }
    }

    // MARK: - FIX: a delimiter row splits its preceding paragraph text off

    @Test("one preceding line splits off, header is the last line")
    func singlePrecedingLine() throws {
        // `x\na\n|-` : `x` becomes a paragraph, `a`+`|-` a single-column table.
        #expect(try blocks("x\na\n|-") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("multiple preceding lines split off as one paragraph")
    func multiplePrecedingLines() throws {
        // `x\ny\na\n|-` : `x\ny` is one paragraph (soft break between), then the table.
        #expect(try blocks("x\ny\na\n|-") == [
            .paragraph("xy"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a body row after the delimiter joins the table")
    func precedingLineWithBodyRow() throws {
        // `x\na\n|-\nb` : `x` paragraph; table header `a`, body row `b`.
        #expect(try blocks("x\na\n|-\nb") == [
            .paragraph("x"),
            .table(header: ["a"], body: [["b"]]),
        ])
    }

    @Test("multi-column header preceded by paragraph text")
    func multiColumnPreceding() throws {
        // `x\na|b\n-|-` : `x` paragraph; two-column table header `a`,`b`.
        #expect(try blocks("x\na|b\n-|-") == [
            .paragraph("x"),
            .table(header: ["a", "b"], body: []),
        ])
    }

    @Test("both-pipes single-column delimiter preceded by text")
    func precedingBothPipes() throws {
        #expect(try blocks("x\na\n|-|") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
        ])
    }

    // MARK: - Break-out still fires after a preceding-paragraph split

    @Test("a lone-pipe line after the delimiter closes the table")
    func lonePipeClosesTable() throws {
        // `x\na\n|-\n|` : the `|` row is zero columns, so it can't extend the table — it re-dispatches
        // as a fresh paragraph, exactly as in the 2-line case.
        #expect(try blocks("x\na\n|-\n|") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
            .paragraph("|"),
        ])
    }

    // MARK: - LEAVE: already-correct shapes must not regress

    @Test("a header that is the paragraph's only line still has no preceding paragraph")
    func bareTwoLineTable() throws {
        #expect(try blocks("a\n|-") == [
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a blank line before the header keeps two separate blocks")
    func blankLineSeparates() throws {
        // `x\n\na\n|-` : the blank line closes `x`, so the table's header is `a` alone.
        #expect(try blocks("x\n\na\n|-") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a dash-only line after preceding text is a setext heading, not a table")
    func setextNotTable() throws {
        // `x\na\n-` : `-` is a setext underline (dash-only), which precedes table detection, so the
        // whole `x\na` becomes a level-2 heading (`x` + soft break + `a`, so the joined literal is "xa").
        #expect(try blocks("x\na\n-") == [.heading("xa")])
    }

    @Test("an ordinary multi-line paragraph with no delimiter stays one paragraph")
    func ordinaryParagraphUnchanged() throws {
        #expect(try blocks("x\ny\nz") == [.paragraph("xyz")])
        #expect(try blocks("a|b\nc|d") == [.paragraph("a|bc|d")])
    }

    // MARK: - Positions: the split nodes must carry valid (present, non-inverted) source ranges

    @Test("split-off paragraph and table carry valid source ranges")
    func splitNodesHaveValidRanges() throws {
        // The split creates a new preceding-paragraph node and re-stamps the table's start to the header
        // line. Both must carry present, non-inverted ranges (the qualified position surface). Positions are
        // unit-gated, not fuzzer-compared, so this is a presence/ordering guard, not a column check.
        let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]
        for source in ["x\na\n|-", "x\ny\na\n|-", "x\na\n|-\nb", "x\na|b\n-|-"] {
            let nodes = try MarkdownDocument.withParsedDocument(source, options: options) {
                doc -> [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] in
                var out: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
                dfsCompleteness(doc.root, into: &out)
                return out
            }
            for node in nodes {
                // Breaks and empty filler cells are legitimately position-less (see
                // SourceRangeCompletenessTests); everything else must be stamped and ordered.
                switch node.kind {
                case .softBreak, .lineBreak:
                    continue
                case .tableCell where node.isLeaf:
                    continue
                default:
                    break
                }
                #expect(node.range != nil, "unstamped \(node.kind) in \(source.debugDescription)")
                if let range = node.range {
                    #expect(range.lowerBound <= range.upperBound,
                            "inverted range on \(node.kind) in \(source.debugDescription)")
                }
            }
        }
    }
}
