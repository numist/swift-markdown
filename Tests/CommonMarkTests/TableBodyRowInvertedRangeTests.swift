/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A table whose header line is indented, `  a|b`, followed by a body row `x` at column 1. cmark re-bases body-row
/// columns to the header's indent, so it reports the row as starting at 3:3 but ending at 3:1 (inclusive), an inverted
/// range. With `.cmarkBugCompatibility` the rewrite re-bases the row's start too, but no range may run past the end of
/// the row's line at column 2, so the start is cut off there and the row collapses to 3:2-3:2. Without it the rewrite
/// reports the row's true extent.
@Suite("Table body row with an inverted re-based range")
struct TableBodyRowInvertedRangeTests {

    private let source = "  a|b\n-|-\nx\n"

    private func bodyRowRange(options: MarkdownDocument.ParseOptions) throws -> Range<MarkdownNode.SourcePosition>?? {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var range: Range<MarkdownNode.SourcePosition>?? = .none
            func walk(_ node: borrowing MarkdownNode) {
                if case .tableRow(isHeader: false) = node.kind {
                    range = .some(node.sourceRange)
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return range
        }
    }

    @Test("with cmark bug compatibility the row's re-based start is cut off at its line's end")
    func lineEndRangeWithBugCompatibility() throws {
        let end = MarkdownNode.SourcePosition(line: 3, column: 2)
        #expect(try bodyRowRange(options: [.tables, .sourcePosition, .cmarkBugCompatibility]) == .some(end..<end))
    }

    @Test("without cmark bug compatibility the row spans its own line")
    func trueRangeWithoutBugCompatibility() throws {
        let start = MarkdownNode.SourcePosition(line: 3, column: 1)
        let end = MarkdownNode.SourcePosition(line: 3, column: 2)
        #expect(try bodyRowRange(options: [.tables, .sourcePosition]) == .some(start..<end))
    }
}
