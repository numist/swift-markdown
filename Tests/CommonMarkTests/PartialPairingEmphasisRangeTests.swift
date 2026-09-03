/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges for emphasis and strong under *partial pairing* - a delimiter run longer than the
/// run it pairs with, so some delimiter characters survive as literal text alongside the node.
///
/// The parser stamps the emphasis/strong node over only the delimiters it consumed plus its
/// content, so its range never overlaps the leftover-delimiter text - the spec-correct behavior.
/// (cmark-gfm instead stretches the node over its whole delimiter run, overlapping the leftover
/// text; the rewrite does not reproduce that non-compliant position.)
@Suite("Emphasis source ranges - partial pairing (spec-correct)")
struct PartialPairingEmphasisRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source range of the first node of `kind`, in DFS order, when `src` is parsed spec-correct.
    private func firstRange(of kind: MarkdownNode.Kind, in src: String) throws -> Range<Pos>? {
        let ranges = try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.first { $0.kind == kind }?.range
    }

    @Test("partial pairing emphasis uses spec-correct (non-overlapping) range")
    func partialPairingEmphasisUsesSpecCorrectRange() throws {
        // `**o*`: opener run `**`, closer run `*`. The emphasis consumes the opener's SECOND `*`
        // (col 2) and the closer `*` (col 4); the first `*` is leftover text. Spec-correct
        // emphasis starts at col 2, excluding that leftover (cmark's quirk starts at col 1).
        let leadingLeftover = try firstRange(of: .emphasis, in: "**o*")
        #expect(leadingLeftover?.lowerBound == Pos(line: 1, column: 2))
        #expect(leadingLeftover?.upperBound == Pos(line: 1, column: 5))

        // `*o**`: opener run `*`, closer run `**`. The emphasis consumes the opener `*` (col 1) and
        // the closer's FIRST `*` (col 3); the trailing `*` is leftover. Spec-correct emphasis ends
        // at col 4, excluding that leftover (cmark's quirk ends at col 5).
        let trailingLeftover = try firstRange(of: .emphasis, in: "*o**")
        #expect(trailingLeftover?.lowerBound == Pos(line: 1, column: 1))
        #expect(trailingLeftover?.upperBound == Pos(line: 1, column: 4))

        // `***o***`: the outer emphasis consumes the outermost `*` on each side (no leftover of its
        // own), so its range spans the whole run. The inner strong consumes cols 2-3 and 5-6 only,
        // so spec-correct it is @1:2-1:7, excluding the outer `*` on each side (cmark's quirk
        // stretches the strong to the full @1:1-1:8, overlapping those outer delimiters).
        let outer = try firstRange(of: .emphasis, in: "***o***")
        #expect(outer?.lowerBound == Pos(line: 1, column: 1))
        #expect(outer?.upperBound == Pos(line: 1, column: 8))
        let inner = try firstRange(of: .strong, in: "***o***")
        #expect(inner?.lowerBound == Pos(line: 1, column: 2))
        #expect(inner?.upperBound == Pos(line: 1, column: 7))
    }
}
