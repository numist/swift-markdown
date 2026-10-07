/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A body row's source range covers its own line, independent of the header row's indentation.
@Suite("Table body row source range after an indented header row")
struct TableBodyRowAfterIndentedHeaderRangeTests {

    private let source = "  a|b\n-|-\nx\n"

    private func bodyRowRange(options: MarkdownDocument.ParseOptions) -> Range<MarkdownNode.SourcePosition>?? {
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

    @Test("a body row at column 1 after an indented header row spans its own line")
    func bodyRowSpansItsOwnLine() {
        let start = MarkdownNode.SourcePosition(line: 3, column: 1)
        let end = MarkdownNode.SourcePosition(line: 3, column: 2)
        #expect(bodyRowRange(options: [.tables, .sourcePosition]) == .some(start..<end))
    }
}
