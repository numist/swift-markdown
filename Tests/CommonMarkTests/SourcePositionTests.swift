/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind and source range. File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see code-conventions: bind docs to locals, use file-scope helpers).
internal func dfsRanges(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?)]
) {
    out.append((node.kind, node.sourceRange))
    node.children.forEach { child in
        dfsRanges(child, into: &out)
    }
}

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
    func offByDefault() throws {
        let src = "# Hi\n\nHello\n"
        try MarkdownDocument.withParsedDocument(src) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        #expect(ranges.allSatisfy { $0.range == nil })
        }
    }

    @Test("heading + paragraph start/end positions")
    func headingParagraph() throws {
        // "# Hi" on line 1, blank line 2, "Hello world" on line 3.
        let src = "# Hi\n\nHello world\n"
        try MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
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
    func blockQuote() throws {
        let src = "> quote\n"
        try MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let bq = range(in: ranges) { $0 == .blockQuote }
        #expect(bq?.lowerBound == Pos(line: 1, column: 1))   // the '>' marker
        #expect(bq?.upperBound == Pos(line: 1, column: 8))   // "> quote" is 7 bytes
        }
    }

    @Test("list item start columns")
    func listItems() throws {
        let src = "- a\n- b\n"
        try MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
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
        // A bare `-` opens an empty item whose content column is 2. cmark's item-continuation
        // rule tests `indent >= content column` before the blank/first-child check, so a
        // following whitespace-only line whose expanded indent reaches column 2 extends the
        // (still childless) item onto it: a tab expands to 4 columns >= 2. The end column is
        // the raw byte offset past the tab (1 tab -> col 2), per the zero-copy source model.
        try MarkdownDocument.withParsedDocument("-\n\t", options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let item = try #require(range(in: ranges) { if case .item = $0 { return true } else { return false } })
        #expect(item.lowerBound == Pos(line: 1, column: 1))
        #expect(item.upperBound == Pos(line: 2, column: 2))
        }

        // Two tabs push the end column one byte further: end is the raw byte offset past the
        // whitespace, so column = tab count + 1 (@2:3), not the expanded column.
        try MarkdownDocument.withParsedDocument("-\n\t\t", options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let item = try #require(range(in: ranges) { if case .item = $0 { return true } else { return false } })
        #expect(item.lowerBound == Pos(line: 1, column: 1))
        #expect(item.upperBound == Pos(line: 2, column: 3))
        }

        // Control: a lone trailing space is only 1 column, below the content column 2, so the
        // empty item does NOT extend - it ends on line 1 (@1:2), as a truly blank line would.
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
        // `- -` opens an outer empty item (marker col 1, content column 3) that itself contains an
        // inner empty item (marker col 3, content column 5). cmark's item continuation tests
        // `indent >= marker_offset + padding` per item, measuring each item's indent relative to the
        // prefix its ancestors already consumed - so a childless item extends onto a following blank
        // line only when that blank reaches its OWN content column, not a shallower ancestor's.

        // Blank indent 2 reaches the OUTER content column (3, i.e. 2 columns of indent past the start)
        // but NOT the inner's (5). So the outer extends onto the blank line while the inner - childless
        // and short of its own content column - ends on its marker line. (Regression: the rewrite used
        // to measure the inner against the outer's content column and wrongly extend it to @2:3.)
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

        // Boundary: 4 columns of indent reach the inner content column (5) exactly, so BOTH the outer
        // and the (childless) inner item extend onto the blank line.
        try MarkdownDocument.withParsedDocument("- -\n    \n", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let items = itemRanges(in: ranges)
            try #require(items.count == 2, "expected an outer + a nested inner item; got \(items.count)")
            let outer = try #require(items[0])
            let inner = try #require(items[1])
            #expect(outer == Pos(line: 1, column: 1)..<Pos(line: 2, column: 5))
            #expect(inner == Pos(line: 1, column: 3)..<Pos(line: 2, column: 5))   // inner extends: indent == its content column
        }

        // Three levels (`- + *`, distinct bullets so it is genuine nesting, not a thematic break) with
        // a blank whose indent (5) lands BETWEEN the middle item's content column (5) and the inner's
        // (7). The outer and middle both stay open - the middle because it still has a child (the inner
        // list) - while the innermost, childless and short of its own content column, ends on its marker
        // line. Pins exactly which level extends when the indent falls between two nesting levels.
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
    func byteColumns() throws {
        // "aé b": a(1 byte) é(2 bytes) space(1) b(1) = 5 bytes.
        let src = "aé b\n"
        try MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let para = range(in: ranges) { $0 == .paragraph }
        #expect(para?.lowerBound == Pos(line: 1, column: 1))
        // End column counts bytes, not characters: utf8.count (5) + 1 for the half-open upper bound.
        #expect(para?.upperBound == Pos(line: 1, column: "aé b".utf8.count + 1))
        }
    }

    @Test("indented code block start column accounts for indentation")
    func indentedCodeStart() throws {
        let src = "    code\n"
        try MarkdownDocument.withParsedDocument(src, options: .sourcePosition) { doc in
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        dfsRanges(doc.root, into: &ranges)
        let code = range(in: ranges) { if case .codeBlock = $0 { return true } else { return false } }
        #expect(code?.lowerBound == Pos(line: 1, column: 5))   // 4 spaces then content
        }
    }
}
