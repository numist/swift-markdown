/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A list item that begins with a blank line cannot interrupt a paragraph (List items), so a list marker with
/// nothing after it, on a line that would otherwise be paragraph continuation text, stays paragraph text. Where the
/// paragraph's container does not continue onto that line, the marker opens a list.
@Suite("Empty list marker paragraph interruption")
struct EmptyListMarkerInterruptTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Every `.list` node's `ListInfo`, in depth-first order: `[0]` is the outermost list.
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

    @Test("empty marker in a continued list item stays paragraph text (no nested list)")
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

    @Test("empty marker on a line without `>` opens a top-level list after the block quote")
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

    @Test("empty marker after a top-level paragraph stays text")
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
