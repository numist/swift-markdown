/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// An EMPTY list marker (`+`/`*`/`-`/`N.` with nothing after it) on a continuation line interrupts an
/// open paragraph under exactly the same rule cmark applies to a non-empty ordered marker: only when the
/// marker does NOT genuinely interrupt that paragraph. cmark's `parse_list_marker` accepts an empty
/// bullet/ordered marker as a new list iff `!interrupts_paragraph` (blocks.c). Concretely the outcome
/// depends on whether the open paragraph's OWN container matched the continuation prefix:
///   - nested inside a list item whose continuation matched → the marker interrupts the item's paragraph
///     → it does NOT open a nested list; it folds back in as continuation text.
///   - after a block quote whose continuation FAILED → only the document matched, which is not the
///     paragraph's parent → the marker is not interrupting that paragraph → it opens a NEW top-level list.
///   - after a top-level paragraph (document is the paragraph's own container, always matches) → the
///     marker interrupts that paragraph → it does NOT open a list (FINDINGS #43).
@Suite("Empty list marker paragraph interruption")
struct EmptyListMarkerInterruptTests {

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

    /// Count of nodes of a given kind anywhere in the tree, selected by `predicate`.
    private func count(
        in ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
        where predicate: (MarkdownNode.Kind) -> Bool
    ) -> Int {
        ranges.reduce(0) { acc, entry in predicate(entry.kind) ? acc + 1 : acc }
    }

    private func parseKinds(
        _ src: String,
        _ body: ([(kind: MarkdownNode.Kind, range: Range<Pos>?)], _ topLevelKinds: [MarkdownNode.Kind]) throws -> Void
    ) throws {
        try MarkdownDocument.withParsedDocument(src) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            var topLevelKinds: [MarkdownNode.Kind] = []
            doc.root.children.forEach { topLevelKinds.append($0.kind) }
            try body(ranges, topLevelKinds)
        }
    }

    /// nested-item context: an empty marker on the item's continuation line does NOT open a nested list;
    /// it stays paragraph text. Applies to bullets (`+`, `*`) and to an empty ordered marker (`2.`) alike,
    /// since the empty-marker rule is decided before the ordered start-number rule.
    @Test("empty marker in a matched list item stays paragraph text (no nested list)")
    func emptyMarkerInNestedItemStaysText() throws {
        for src in ["- a\n  +", "- a\n  *", "- a\n  2."] {
            try parseKinds(src) { ranges, _ in
                let lists = listInfos(in: ranges)
                try #require(lists.count >= 1, "fixture \(src.debugDescription) must parse to at least the outer list; got \(lists.count)")
                #expect(lists.count == 1)                                    // no nested list opened
                #expect(lists[0].kind == .bullet)
                #expect(count(in: ranges) { if case .item = $0 { return true }; return false } == 1)
            }
        }
    }

    /// after-unmatched-bq context: a block quote's continuation fails on a line with no `>`, so an empty
    /// marker there is NOT interrupting the (now-closed) block-quote paragraph - it opens a NEW top-level
    /// list, a sibling of the block quote.
    @Test("empty marker after an unmatched block quote opens a new top-level list")
    func emptyMarkerAfterUnmatchedBlockQuoteOpensTopLevelList() throws {
        try parseKinds("> a\n+") { ranges, topLevelKinds in
            try #require(topLevelKinds.count == 2, "expected two top-level blocks (block quote + list); got \(topLevelKinds)")
            #expect({ if case .blockQuote = topLevelKinds[0] { return true }; return false }())
            #expect({ if case .list = topLevelKinds[1] { return true }; return false }())
            let lists = listInfos(in: ranges)
            #expect(lists.count == 1)
            #expect(lists[0].kind == .bullet)
            #expect(count(in: ranges) { if case .blockQuote = $0 { return true }; return false } == 1)
            #expect(count(in: ranges) { if case .item = $0 { return true }; return false } == 1)
        }
    }

    /// top-level context (FINDINGS #43): the document is the top paragraph's own container and always
    /// matches, so an empty marker interrupts that paragraph - meaning it CANNOT, and stays text. No list.
    @Test("empty marker after a top-level paragraph stays text (FINDINGS #43)")
    func emptyMarkerAfterTopLevelParagraphStaysText() throws {
        for src in ["a\n+", "a\n* "] {
            try parseKinds(src) { ranges, topLevelKinds in
                try #require(topLevelKinds.count == 1, "fixture \(src.debugDescription) must parse to a single top-level block; got \(topLevelKinds)")
                #expect({ if case .paragraph = topLevelKinds[0] { return true }; return false }())
                #expect(listInfos(in: ranges).isEmpty)                       // no list opened
            }
        }
    }
}
