/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Coverage for source-position stamping of inline runs that fall on the 2nd+ physical line of a
/// **multi-line contiguous** segment.
///
/// A top-level paragraph whose first lines are source-adjacent (LF, no stripped prefix) collapses those
/// lines into ONE `inSource` segment (`a\nb`) that spans multiple physical source lines with
/// `sourceOffset == offset` (no re-indent). When a LATER line has leading whitespace, the paragraph turns
/// non-contiguous (a segment list), so the earlier contiguous run is preserved as that single multi-line
/// segment. An inline run on such a segment's interior line projects onto the run's own physical line
/// (its byte projection is already exact, since the run is not re-indented). (Regression for the
/// differential-fuzzer `midseg-*` pairs.)
@Suite("Multi-line contiguous segment - interior-line inline positions")
struct MultiLineSegmentRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func ranges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out
    }

    /// The deliverable (flag-OFF, spec-correct default): every inline on an interior contiguous line
    /// carries its true byte-projected position - notably line 2's `b` at `@2:1-2:2`.
    @Test("flag-OFF: interior line b is stamped @2:1-2:2")
    func specInteriorLineStamped() throws {
        let texts = ranges("a\nb\n c", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 3))   // "c" (spec: true column)
    }

    /// The final re-indented line keeps its true byte-projected
    /// column (@4:2).
    @Test("flag-OFF: four-line paragraph keeps the final re-indented line's true column")
    func specFourLine() throws {
        let texts = ranges("a\nb\nc\n d", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 4)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b"
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "c"
        #expect(texts[3] == Pos(line: 4, column: 2)..<Pos(line: 4, column: 3))   // "d" true column (spec)
    }

    /// A single-line emphasis on an interior contiguous line is stamped on its own physical line.
    @Test("flag-OFF: single-line emphasis on an interior contiguous line is stamped on its own line")
    func specInteriorEmphasis() {
        let all = ranges("a\n*b*\n c", options: Self.specOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let innerText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 2)) }?.range
        #expect(emph == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))       // "*b*"
        #expect(innerText == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))  // "b"
    }

    /// A genuine multi-line WRAPPER (`*a\nb*`) inside a contiguous segment keeps its opener on line 1 and
    /// its closer on line 2 - the byte projection is exact, so it is NOT collapsed onto line 1.
    @Test("flag-OFF: multi-line wrapper on a contiguous segment keeps its closer on line 2")
    func specMultiLineWrapper() {
        let all = ranges("*a\nb*\n c", options: Self.specOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let bText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 1)) }?.range
        #expect(emph == Pos(line: 1, column: 1)..<Pos(line: 2, column: 3))       // "*a\nb*"
        #expect(bText == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))      // "b" on line 2
    }
}
