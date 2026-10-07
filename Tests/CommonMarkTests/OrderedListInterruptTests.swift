/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// An ordered list can interrupt a paragraph only when its start number is 1 (List items); otherwise the
/// marker is paragraph continuation text. The rule applies at every nesting level.
@Suite("Ordered list paragraph interruption")
struct OrderedListInterruptTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Every `.list` node's `ListInfo`, in DFS (document) order: `[0]` is the outermost list.
    private func listInfos(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> [MarkdownNode.ListInfo] {
        ranges.compactMap { entry in
            if case .list(let info) = entry.kind { return info }
            return nil
        }
    }

    /// Count of `.item` nodes anywhere in the tree.
    private func itemCount(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Int {
        ranges.reduce(0) { acc, entry in
            if case .item = entry.kind { return acc + 1 }
            return acc
        }
    }

    private func parseKinds(
        _ src: String,
        _ body: ([(kind: MarkdownNode.Kind, range: Range<Pos>?)]) throws -> Void
    ) throws {
        try MarkdownDocument.withParsedDocument(src) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            try body(ranges)
        }
    }

    @Test("nested ordered start != 1 stays paragraph text; ordered-1 and bullets interrupt")
    func nestedInterruptRequiresOrderedStartOne() throws {
        try parseKinds("- a\n  2. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count >= 1, "fixture must parse to at least the outer list; got \(lists.count)")
            #expect(lists.count == 1)
            #expect(lists[0].kind == .bullet)
            #expect(itemCount(in: ranges) == 1)
        }

        try parseKinds("- a\n  1. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 2, "expected outer bullet + nested ordered list; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .ordered)
            #expect(lists[1].start == 1)
        }

        try parseKinds("- a\n  - b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 2, "expected two nested bullet lists; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .bullet)
        }
    }

    /// `2. b` is not indented into the first item, so it starts a sibling item rather than
    /// interrupting the item's paragraph.
    @Test("a sibling ordered marker (start != 1) at the list level opens a new item")
    func siblingOrderedMarkerOpensNewItem() throws {
        try parseKinds("1. a\n2. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 1, "expected a single ordered list containing two items; got \(lists.count)")
            #expect(lists[0].kind == .ordered)
            #expect(lists[0].start == 1)
            #expect(itemCount(in: ranges) == 2)
        }
    }

    @Test("nested ordered start 10 (multi-digit, != 1) stays paragraph text")
    func multiDigitStartDoesNotInterrupt() throws {
        try parseKinds("- a\n  10. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count >= 1, "fixture must parse to at least the outer list; got \(lists.count)")
            #expect(lists.count == 1)
            #expect(lists[0].kind == .bullet)
            #expect(itemCount(in: ranges) == 1)
        }
    }

    @Test("nested ordered start != 1 with a paren delimiter stays paragraph text")
    func parenDelimiterStartTwoDoesNotInterrupt() throws {
        try parseKinds("- a\n  2) b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count >= 1, "fixture must parse to at least the outer list; got \(lists.count)")
            #expect(lists.count == 1)
            #expect(lists[0].kind == .bullet)
            #expect(itemCount(in: ranges) == 1)
        }
    }

    @Test("ordered-1 interrupts a paragraph at a deeper nesting level")
    func orderedOneInterruptsAtDeeperLevel() throws {
        try parseKinds("- - a\n    1. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 3, "expected two bullet levels + a nested ordered list; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .bullet)
            #expect(lists[2].kind == .ordered)
            #expect(lists[2].start == 1)
        }
    }

    @Test("ordered start != 1 as the first block forms a list")
    func orderedStartTwoAsFirstBlockFormsList() throws {
        try parseKinds("2. a") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 1, "expected a single ordered list; got \(lists.count)")
            #expect(lists[0].kind == .ordered)
            #expect(lists[0].start == 2)
            #expect(itemCount(in: ranges) == 1)
        }
    }
}
