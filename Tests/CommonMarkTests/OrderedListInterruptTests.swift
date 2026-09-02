/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A list marker inside a list item's open paragraph opens a *nested* list only if it can interrupt
/// that paragraph (CommonMark 0.31 §5.3). A bullet always can; an ORDERED list can only when its start
/// number is 1. Otherwise the marker folds back into the paragraph as continuation text - it does NOT
/// open a nested list. This mirrors cmark's `parse_list_marker` (`interrupts_paragraph && start != 1`
/// declines the marker) and applies at every nesting level, not just the top.
@Suite("Ordered list paragraph interruption - §5.3")
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

    /// The core rule: a nested ordered marker with start != 1 stays paragraph text (no nested list),
    /// while an ordered-1 marker and any bullet marker interrupt and open a nested list.
    @Test("nested ordered start != 1 stays paragraph text; ordered-1 and bullets interrupt")
    func nestedInterruptRequiresOrderedStartOne() throws {
        // start = 2: `2. b` is continuation text of the item's paragraph, so only the outer bullet list
        // exists (one item, one paragraph). No nested list is opened.
        try parseKinds("- a\n  2. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count >= 1, "fixture must parse to at least the outer list; got \(lists.count)")
            #expect(lists.count == 1)                 // no nested list opened
            #expect(lists[0].kind == .bullet)
            #expect(itemCount(in: ranges) == 1)       // `2. b` did not open a second item
        }

        // start = 1: the ordered marker DOES interrupt and opens a nested ordered list (start 1).
        try parseKinds("- a\n  1. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 2, "expected outer bullet + nested ordered list; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .ordered)
            #expect(lists[1].start == 1)
        }

        // A bullet marker always interrupts, regardless of the start-number rule (bullets are exempt).
        try parseKinds("- a\n  - b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 2, "expected two nested bullet lists; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .bullet)
        }
    }

    /// The restriction is scoped to marker that genuinely INTERRUPTS the open paragraph. A second
    /// ordered marker at the SAME list level (`2. b` under `1. a`, indent 0) does not interrupt the
    /// item's paragraph - the item's continuation fails first, so the marker opens a sibling item in
    /// the existing list regardless of its start number. This guards the discriminator: the rule must
    /// NOT fire here, or a running list `1. a\n2. b\n3. c ...` would collapse into paragraph text.
    @Test("a sibling ordered marker (start != 1) at the list level still opens a new item")
    func siblingOrderedMarkerOpensNewItem() throws {
        try parseKinds("1. a\n2. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 1, "expected a single ordered list containing two items; got \(lists.count)")
            #expect(lists[0].kind == .ordered)
            #expect(lists[0].start == 1)
            #expect(itemCount(in: ranges) == 2)   // `2. b` opened a second sibling item, not text
        }
    }

    /// A multi-digit start number that is not 1 (e.g. 10) is still barred from interrupting.
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

    /// The delimiter style is irrelevant: a `)` ordered marker with start != 1 is barred just like `.`.
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

    /// The interrupt rule applies at every depth: an ordered-1 marker interrupts a paragraph two levels
    /// deep and opens a nested ordered list there.
    @Test("ordered-1 interrupts a paragraph at a deeper nesting level")
    func orderedOneInterruptsAtDeeperLevel() throws {
        // `- - a` is bullet > item > bullet > item > paragraph "a"; `    1. b` (indent 4, the inner
        // item's content column) interrupts that paragraph and opens a nested ordered list.
        try parseKinds("- - a\n    1. b") { ranges in
            let lists = listInfos(in: ranges)
            try #require(lists.count == 3, "expected two bullet levels + a nested ordered list; got \(lists.count)")
            #expect(lists[0].kind == .bullet)
            #expect(lists[1].kind == .bullet)
            #expect(lists[2].kind == .ordered)
            #expect(lists[2].start == 1)
        }
    }

    /// The start != 1 rule is about *interrupting a paragraph*, not about forming a list at all: an
    /// ordered marker with start != 1 as the very first block still opens a list (starting at that
    /// number). There is no paragraph to interrupt here.
    @Test("ordered start != 1 as the first block still forms a list")
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
