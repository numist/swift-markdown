/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A single line may open at most `BlockParser.maxListNesting` (100) containers before it stops opening
/// lists, matching cmark's `MAX_LIST_DEPTH` gate in `open_new_blocks` (`depth < MAX_LIST_DEPTH`). The
/// depth is counted per line, so N block quotes followed by a list marker put the marker at depth N+1:
/// the list opens while N+1 is below the cap and is suppressed - the marker folds into a paragraph as
/// text - once it reaches the cap. Block quotes themselves are uncapped. cmark applies this to bullet
/// AND ordered lists, and it is intentional (not a bug), so the cap holds regardless of
/// `.cmarkBugCompatibility`.
@Suite("List nesting depth cap - cmark MAX_LIST_DEPTH")
struct ListNestingDepthCapTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Every parsed node's kind, in DFS (document) order.
    private func parseKinds(
        _ src: String,
        options: MarkdownDocument.ParseOptions,
        _ body: ([MarkdownNode.Kind]) throws -> Void
    ) throws {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            try body(ranges.map(\.kind))
        }
    }

    private func listCount(_ kinds: [MarkdownNode.Kind]) -> Int {
        kinds.reduce(0) { if case .list = $1 { return $0 + 1 }; return $0 }
    }

    private func itemCount(_ kinds: [MarkdownNode.Kind]) -> Int {
        kinds.reduce(0) { if case .item = $1 { return $0 + 1 }; return $0 }
    }

    private func blockQuoteCount(_ kinds: [MarkdownNode.Kind]) -> Int {
        kinds.reduce(0) { if case .blockQuote = $1 { return $0 + 1 }; return $0 }
    }

    /// Both flag modes: the cap is cmark's intentional behavior, not gated on `.cmarkBugCompatibility`.
    private static let flagModes: [MarkdownDocument.ParseOptions] = [[], [.cmarkBugCompatibility]]

    /// Just below the cap - 98 block quotes put the bullet marker at depth 99 (< 100) - so the list opens.
    /// At the cap - 99 block quotes put it at depth 100 - the marker stays paragraph text and no list opens.
    @Test("bullet list opens at depth 99 but not at the cap (depth 100)")
    func bulletListCappedAtMaxDepth() throws {
        for options in Self.flagModes {
            // 98 quotes: the marker is the 99th container on the line, below the cap, so a list opens.
            try parseKinds(String(repeating: ">", count: 98) + "- ", options: options) { kinds in
                #expect(blockQuoteCount(kinds) == 98, "fixture must nest 98 block quotes; got \(blockQuoteCount(kinds))")
                #expect(listCount(kinds) == 1, "options=\(options.rawValue): expected a list just below the cap")
                #expect(itemCount(kinds) == 1)
            }

            // 99 quotes: the marker is the 100th container, at the cap, so it stays text - no list.
            try parseKinds(String(repeating: ">", count: 99) + "- ", options: options) { kinds in
                #expect(blockQuoteCount(kinds) == 99, "fixture must nest 99 block quotes; got \(blockQuoteCount(kinds))")
                #expect(listCount(kinds) == 0, "options=\(options.rawValue): list must be suppressed at the cap")
                #expect(itemCount(kinds) == 0)
                #expect(kinds.contains { $0 == .paragraph }, "the marker must fall through to a paragraph")
            }
        }
    }

    /// The cap applies to ordered lists identically (cmark gates `parse_list_marker` for both).
    @Test("ordered list opens at depth 99 but not at the cap (depth 100)")
    func orderedListCappedAtMaxDepth() throws {
        for options in Self.flagModes {
            try parseKinds(String(repeating: ">", count: 98) + "1. ", options: options) { kinds in
                #expect(blockQuoteCount(kinds) == 98, "fixture must nest 98 block quotes; got \(blockQuoteCount(kinds))")
                #expect(listCount(kinds) == 1, "options=\(options.rawValue): expected an ordered list just below the cap")
                #expect(itemCount(kinds) == 1)
            }

            try parseKinds(String(repeating: ">", count: 99) + "1. ", options: options) { kinds in
                #expect(blockQuoteCount(kinds) == 99, "fixture must nest 99 block quotes; got \(blockQuoteCount(kinds))")
                #expect(listCount(kinds) == 0, "options=\(options.rawValue): ordered list must be suppressed at the cap")
                #expect(itemCount(kinds) == 0)
                #expect(kinds.contains { $0 == .paragraph }, "the marker must fall through to a paragraph")
            }
        }
    }
}
