/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a delimiter row follows a paragraph of several lines, the paragraph's last line is the header
/// row and the earlier lines remain a paragraph (Tables (extension)).
@Suite("Table takes a paragraph's last line as its header row")
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
    ) -> [Block] {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> [Block] in
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

    // MARK: - Earlier lines remain a paragraph

    @Test("one preceding line splits off, header is the last line")
    func singlePrecedingLine() throws {
        #expect(try blocks("x\na\n|-") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("multiple preceding lines split off as one paragraph")
    func multiplePrecedingLines() throws {
        #expect(try blocks("x\ny\na\n|-") == [
            .paragraph("xy"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a body row after the delimiter joins the table")
    func precedingLineWithBodyRow() throws {
        #expect(try blocks("x\na\n|-\nb") == [
            .paragraph("x"),
            .table(header: ["a"], body: [["b"]]),
        ])
    }

    @Test("multi-column header preceded by paragraph text")
    func multiColumnPreceding() throws {
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

    // MARK: - Closing the table

    @Test("a lone-pipe line after the delimiter closes the table")
    func lonePipeClosesTable() throws {
        // A lone `|` has no cells, so it is not a body row.
        #expect(try blocks("x\na\n|-\n|") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
            .paragraph("|"),
        ])
    }

    // MARK: - No earlier lines

    @Test("a header that is the paragraph's only line has no preceding paragraph")
    func bareTwoLineTable() throws {
        #expect(try blocks("a\n|-") == [
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a blank line before the header keeps two separate blocks")
    func blankLineSeparates() throws {
        #expect(try blocks("x\n\na\n|-") == [
            .paragraph("x"),
            .table(header: ["a"], body: []),
        ])
    }

    @Test("a dash-only line after preceding text is a setext heading, not a table")
    func setextNotTable() {
        // A line of only dashes is a setext heading underline, which takes the whole paragraph
        // (Setext headings).
        #expect(blocks("x\na\n-") == [.heading("xa")])
    }

    @Test("a multi-line paragraph with no delimiter row stays one paragraph")
    func paragraphWithoutDelimiterRow() {
        #expect(blocks("x\ny\nz") == [.paragraph("xyz")])
        #expect(blocks("a|b\nc|d") == [.paragraph("a|bc|d")])
    }

    // MARK: - Source ranges

    @Test("split-off paragraph and table carry valid source ranges")
    func splitNodesHaveValidRanges() {
        let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]
        for source in ["x\na\n|-", "x\ny\na\n|-", "x\na\n|-\nb", "x\na|b\n-|-"] {
            let nodes = MarkdownDocument.withParsedDocument(source, options: options) {
                doc -> [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] in
                var out: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
                dfsCompleteness(doc.root, into: &out)
                return out
            }
            for node in nodes {
                // Line breaks and empty cells have no source range (see SourceRangeCompletenessTests).
                switch node.kind {
                case .softBreak, .lineBreak:
                    continue
                case .tableCell where node.isLeaf:
                    continue
                default:
                    break
                }
                #expect(node.range != nil, "missing source range on \(node.kind) in \(source.debugDescription)")
                if let range = node.range {
                    #expect(range.lowerBound <= range.upperBound,
                            "inverted range on \(node.kind) in \(source.debugDescription)")
                }
            }
        }
    }
}
