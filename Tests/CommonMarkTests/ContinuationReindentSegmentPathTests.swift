/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark bug-compatible (flag-ON) coverage for the continuation re-indent quirk on the *segment* content
/// path, specifically a re-indented MIDDLE continuation line whose re-indented end crosses a physical
/// line boundary.
///
/// Flag-ON re-indent maps a continuation line's surviving content to the block's fixed content column
/// (`BlockParser.addLineSegment`). For a middle line, that pushes the run's mapped source offsets
/// rightward past the line's own byte extent, so the byte-projected end lands on the NEXT physical line;
/// `InlineParser.stampInline` stamps an explicit `(line, column)` end to keep it on the start line
/// (mirroring `stampCloseBracketEnd`'s explicit end for multi-line links). The two-line last-line case is
/// covered by the `s560-*` fuzzer pairs; the `.lazy`-contiguity route (marker-less lazy continuation) by
/// the `s24-lazy-*` pairs. This suite covers the third combination: a *genuinely non-contiguous*
/// (marker-present, prefix-stripped → segment list) MIDDLE line, which the fuzzer oracle pairs don't yet
/// include. Columns are reasoned from cmark's re-indent (validated by `s560-blockquote-para-ctl`, the same
/// marker-present re-indent on a final line), not snapshotted.
@Suite("Continuation re-indent - segment-path middle line (cmark bug-compatible)")
struct ContinuationReindentSegmentPathTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Source positions on, cmark bug-compatibility ON - the differential-fuzzer configuration.
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    @Test("marker-present indented middle continuation re-indents each line to the content column")
    func markerPresentMiddleContinuation() throws {
        // ">   bar" (three spaces after `>` → content column 5), then "> baz" and "> qux" (marker + one
        // space). Every continuation line carries a `> ` prefix that is stripped, so the paragraph body
        // is a genuinely non-contiguous segment list (not the `.lazy` collapse the `s24-*` pairs use).
        // Flag-ON, cmark fixes the content column at 5 and re-indents every line there:
        //   bar @1:5-1:8, baz @2:5-2:8, qux @3:5-3:8.
        // `baz` is a MIDDLE re-indented line: its re-indented end (source column 8 on line 2) projects to
        // a byte offset on line 3, so it can only be reported at @2:8 via the explicit-end stamp.
        var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(">   bar\n> baz\n> qux", options: Self.quirkOptions) { doc in
            dfsRanges(doc.root, into: &ranges)
        }
        let texts = ranges.filter { $0.kind == .text }.map { $0.range }
        try #require(texts.count == 3)

        #expect(texts[0]?.lowerBound == Pos(line: 1, column: 5))   // "bar"
        #expect(texts[0]?.upperBound == Pos(line: 1, column: 8))
        #expect(texts[1]?.lowerBound == Pos(line: 2, column: 5))   // "baz" re-indented, middle line
        #expect(texts[1]?.upperBound == Pos(line: 2, column: 8))   // explicit end keeps it on line 2
        #expect(texts[2]?.lowerBound == Pos(line: 3, column: 5))   // "qux"
        #expect(texts[2]?.upperBound == Pos(line: 3, column: 8))
    }
}
