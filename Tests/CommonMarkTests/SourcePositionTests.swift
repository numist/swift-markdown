/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

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

    /// Every `.item` node's range, in document (DFS) order. For nested lists this is
    /// outermost-first, so `[0]` is the outer item, `[1]` the next level in, and so on.
    private func itemRanges(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> [Range<Pos>?] {
        ranges.compactMap { entry in
            if case .item = entry.kind { return entry.range }
            return nil
        }
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

        // MarkdownDocument spans the whole source: 1:1 .. just past "Hello world" (3:12).
        let docRange = ranges[0].range
        #expect(docRange?.lowerBound == Pos(line: 1, column: 1))
        #expect(docRange?.upperBound == Pos(line: 3, column: 12))

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

    @Test("empty list item extends into a trailing tab continuation line")
    func emptyItemTabContinuation() throws {
        // A whitespace-only line that reaches the empty item's content column (2) extends the item. A
        // tab is 4 columns but one byte, so the item ends at column 2.
        try MarkdownDocument.withParsedDocument("-\n\t", options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let item = try #require(range(in: ranges) { if case .item = $0 { return true } else { return false } })
        #expect(item.lowerBound == Pos(line: 1, column: 1))
        #expect(item.upperBound == Pos(line: 2, column: 2))
        }

        try MarkdownDocument.withParsedDocument("-\n\t\t", options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let item = try #require(range(in: ranges) { if case .item = $0 { return true } else { return false } })
        #expect(item.lowerBound == Pos(line: 1, column: 1))
        #expect(item.upperBound == Pos(line: 2, column: 3))
        }

        // One space falls short of the content column, so the item ends on line 1.
        try MarkdownDocument.withParsedDocument("-\n ", options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let item = try #require(range(in: ranges) { if case .item = $0 { return true } else { return false } })
        #expect(item.lowerBound == Pos(line: 1, column: 1))
        #expect(item.upperBound == Pos(line: 1, column: 2))
        }
    }

    @Test("a nested empty list item extends onto a blank line only when the blank reaches its OWN content column")
    func nestedEmptyItemBlankLineExtent() throws {
        // `- -` is an outer item (content column 3) holding an empty inner item (content column 5).
        // Two spaces reach only the outer item's content column.
        try MarkdownDocument.withParsedDocument("- -\n  \n", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let items = itemRanges(in: ranges)
            try #require(items.count == 2, "expected an outer + a nested inner item; got \(items.count)")
            let outer = try #require(items[0])
            let inner = try #require(items[1])
            #expect(outer == Pos(line: 1, column: 1)..<Pos(line: 2, column: 3))   // outer extends onto the blank
            #expect(inner == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // inner does NOT extend
        }

        // Four spaces reach the inner item's content column.
        try MarkdownDocument.withParsedDocument("- -\n    \n", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let items = itemRanges(in: ranges)
            try #require(items.count == 2, "expected an outer + a nested inner item; got \(items.count)")
            let outer = try #require(items[0])
            let inner = try #require(items[1])
            #expect(outer == Pos(line: 1, column: 1)..<Pos(line: 2, column: 5))
            #expect(inner == Pos(line: 1, column: 3)..<Pos(line: 2, column: 5))   // inner extends
        }

        // Distinct bullets nest three items rather than form a thematic break. Five spaces reach the
        // middle item's content column but not the empty innermost item's (7).
        try MarkdownDocument.withParsedDocument("- + *\n     \n", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let items = itemRanges(in: ranges)
            try #require(items.count == 3, "expected three nested items; got \(items.count)")
            let outer = try #require(items[0])
            let middle = try #require(items[1])
            let inner = try #require(items[2])
            #expect(outer == Pos(line: 1, column: 1)..<Pos(line: 2, column: 6))
            #expect(middle == Pos(line: 1, column: 3)..<Pos(line: 2, column: 6))  // stays open: has a child
            #expect(inner == Pos(line: 1, column: 5)..<Pos(line: 1, column: 6))   // childless, does NOT extend
        }
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
        // End column counts bytes, not characters: utf8.count (5) + 1 for the half-open upper bound.
        #expect(para?.upperBound == Pos(line: 1, column: "aé b".utf8.count + 1))
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
