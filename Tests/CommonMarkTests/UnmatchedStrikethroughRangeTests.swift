/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for an *unmatched* strikethrough (`~`/`~~`) run - a delimiter run that never
/// pairs into a strikethrough, so it survives as literal text.
///
/// The shipped (flag-off, spec-correct) parser stamps such a run with a normal, width-bearing
/// range - its true character span - exactly like any other literal text run. cmark-gfm's
/// degenerate zero-width range (`strikethrough.c` `match` sets only `start_column`, leaving
/// `end_column == 0`) is the `.cmarkBugCompatibility` quirk, covered by the `strike-standalone-*`
/// / `strike-merged-*` fuzzer regression pairs (which parse flag-on); this suite is the flag-off
/// guardrail proving the default parser is spec-correct.
@Suite("Unmatched strikethrough source ranges (spec-correct)")
struct UnmatchedStrikethroughRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source range of the first text node, in DFS order, when `src` is parsed spec-correct.
    private func firstTextRange(in src: String) throws -> Range<Pos>? {
        let ranges = try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.first { $0.kind == .text }?.range
    }

    @Test("standalone unmatched ~ gets a normal, width-bearing range")
    func standaloneSingleTilde() throws {
        // A lone `~` is one byte at column 1; spec-correct it spans its own character (@1:1-1:2),
        // not cmark's zero-width @1:1.
        let range = try firstTextRange(in: "~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 2))
    }

    @Test("standalone unmatched ~~ gets a normal, width-bearing range")
    func standaloneDoubleTilde() throws {
        // `~~` is two bytes; spec-correct it spans both (@1:1-1:3), not cmark's zero-width @1:1.
        let range = try firstTextRange(in: "~~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 3))
    }

    @Test("trailing unmatched ~ merges into a normally-ranged text run")
    func trailingTilde() throws {
        // `a~`: the `a` and the trailing `~` consolidate into one text node. Spec-correct the merged
        // run ends past the `~` (@1:1-1:3); cmark's zero-width `~` collapses the merge to @1:1.
        let range = try firstTextRange(in: "a~")
        #expect(range?.lowerBound == Pos(line: 1, column: 1))
        #expect(range?.upperBound == Pos(line: 1, column: 3))
    }
}
