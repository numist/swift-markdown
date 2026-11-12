/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Source positions - blocks")
struct SourcePositionTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Find the first node whose kind matches `predicate` and return its range.
    private func range(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
        where predicate: (MarkdownNode.Kind) -> Bool
    ) -> Range<Pos>? {
        for entry in ranges where predicate(entry.kind) {
            return entry.range
        }
        return nil
    }

    @Test("off by default - sourceRange is nil without .sourcePosition")
    func offByDefault() {
        let src = "# Hi\n\nHello\n"
        MarkdownDocument.withParsedDocument(src) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        #expect(ranges.allSatisfy { $0.range == nil })
        }
    }

    @Test("heading + paragraph start/end positions")
    func headingParagraph() {
        // "# Hi" on line 1, blank line 2, "Hello world" on line 3.
        let src = "# Hi\n\nHello world\n"
        MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)

        // The document spans the whole source, through the final line ending.
        let docRange = ranges[0].range
        #expect(docRange?.lowerBound == Pos(line: 1, column: 1))
        #expect(docRange?.upperBound == Pos(line: 4, column: 1))

        let heading = range(in: ranges) { if case .heading = $0 { return true } else { return false } }
        #expect(heading?.lowerBound == Pos(line: 1, column: 1))
        #expect(heading?.upperBound == Pos(line: 1, column: 5))   // "# Hi" is 4 bytes

        let para = range(in: ranges) { $0 == .paragraph }
        #expect(para?.lowerBound == Pos(line: 3, column: 1))
        #expect(para?.upperBound == Pos(line: 3, column: 12))     // "Hello world" is 11 bytes
        }
    }

    @Test("block quote start/end")
    func blockQuote() {
        let src = "> quote\n"
        MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let bq = range(in: ranges) { $0 == .blockQuote }
        #expect(bq?.lowerBound == Pos(line: 1, column: 1))   // the '>' marker
        #expect(bq?.upperBound == Pos(line: 1, column: 8))   // "> quote" is 7 bytes
        }
    }

    @Test("list item start columns")
    func listItems() {
        let src = "- a\n- b\n"
        MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)

        let list = range(in: ranges) { if case .list = $0 { return true } else { return false } }
        #expect(list?.lowerBound == Pos(line: 1, column: 1))

        // Both items start at column 1 (the bullet marker), on their own lines.
        var itemStarts: [Pos] = []
        for entry in ranges {
            if case .item = entry.kind, let lo = entry.range?.lowerBound { itemStarts.append(lo) }
        }
        #expect(itemStarts == [Pos(line: 1, column: 1), Pos(line: 2, column: 1)])
        }
    }

    @Test("empty list item ends before a trailing whitespace-only line")
    func emptyItemWhitespaceLine() {
        // An item's range ends just past its last content byte, and a line of only spaces or tabs holds none, however
        // far it is indented.
        #expect(TreeDump.dump("-\n\t", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2

            """)
        #expect(TreeDump.dump("-\n\t\t", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:3
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2

            """)
        #expect(TreeDump.dump("-\n ", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-1:2
                item @1:1-1:2

            """)
    }

    @Test("nested list items end at their last content byte, before a following blank line")
    func nestedEmptyItemBlankLineExtent() {
        // `- -` is an outer item (content column 3) holding an empty inner item (content column 5).
        // Two spaces reach only the outer item's content column.
        #expect(TreeDump.dump("- -\n  \n", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:4
                item @1:1-1:4
                  list bullet '-' tight @1:3-1:4
                    item @1:3-1:4

            """)

        // Four spaces reach the inner item's content column, but the inner item is empty.
        #expect(TreeDump.dump("- -\n    \n", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:4
                item @1:1-1:4
                  list bullet '-' tight @1:3-1:4
                    item @1:3-1:4

            """)

        // Distinct bullets nest three items rather than form a thematic break. Five spaces reach the
        // middle item's content column but not the empty innermost item's (7).
        #expect(TreeDump.dump("- + *\n     \n", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  list bullet '+' tight @1:3-1:6
                    item @1:3-1:6
                      list bullet '*' tight @1:5-1:6
                        item @1:5-1:6

            """)
    }

    @Test("columns are 1-based UTF-8 byte offsets (non-ASCII)")
    func byteColumns() {
        // "aé b": a(1 byte) é(2 bytes) space(1) b(1) = 5 bytes.
        let src = "aé b\n"
        MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let para = range(in: ranges) { $0 == .paragraph }
        #expect(para?.lowerBound == Pos(line: 1, column: 1))
        #expect(para?.upperBound == Pos(line: 1, column: 6))
        }
    }

    @Test("indented code block start column accounts for indentation")
    func indentedCodeStart() {
        let src = "    code\n"
        MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let code = range(in: ranges) { if case .codeBlock = $0 { return true } else { return false } }
        #expect(code?.lowerBound == Pos(line: 1, column: 5))   // 4 spaces then content
        }
    }
}
