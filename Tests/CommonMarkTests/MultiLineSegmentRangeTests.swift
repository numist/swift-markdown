/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
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
/// segment. Stamping a run on such a segment's interior line must project onto the run's own physical line;
/// the flag-ON Quirk-E overshoot correction (`InlineParser.stampInline`) must NOT fire, because that run
/// is not re-indented and its byte projection is already exact. (Regression for the differential-fuzzer
/// `midseg-*` pairs.)
@Suite("Multi-line contiguous segment - interior-line inline positions")
struct MultiLineSegmentRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    private func ranges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out
    }

    /// The deliverable (flag-OFF, spec-correct default): every inline on an interior contiguous line
    /// carries its true byte-projected position - notably line 2's `b` at `@2:1-2:2`.
    @Test("flag-OFF: interior line b is stamped @2:1-2:2")
    func specInteriorLineStamped() throws {
        let texts = try ranges("a\nb\n c", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 3))   // "c" (spec: true column)
    }

    /// Flag-ON (differential-fuzzer configuration). The `midseg-*` oracle values (minted from cmark-gfm):
    /// each interior contiguous-line text run keeps its own physical line's position; only the final
    /// re-indented line moves to column 1.
    @Test("flag-ON: three-line paragraph stamps every text run on its own line")
    func quirkThreeLine() throws {
        let texts = try ranges("a\nb\n c", options: Self.quirkOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b"
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "c" re-indented to col 1
    }

    @Test("flag-ON: four-line paragraph stamps both interior lines")
    func quirkFourLine() throws {
        let texts = try ranges("a\nb\nc\n d", options: Self.quirkOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 4)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b"
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "c"
        #expect(texts[3] == Pos(line: 4, column: 1)..<Pos(line: 4, column: 2))   // "d" re-indented to col 1
    }

    @Test("flag-ON: single-line emphasis on an interior contiguous line is stamped")
    func quirkInteriorEmphasis() throws {
        let all = try ranges("a\n*b*\n c", options: Self.quirkOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let innerText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 2)) }?.range
        #expect(emph == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))       // "*b*"
        #expect(innerText == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))  // "b"
    }

    /// A genuine multi-line WRAPPER (`*a\nb*`) inside a contiguous segment (branch 2 of the overshoot
    /// correction). With no re-indent, the flag-ON emphasis must match the spec-correct byte projection:
    /// opener on line 1, closer on line 2 - not collapsed onto line 1.
    @Test("flag-ON: multi-line wrapper on a contiguous segment keeps its closer on line 2")
    func quirkMultiLineWrapper() throws {
        let all = try ranges("*a\nb*\n c", options: Self.quirkOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let bText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 1)) }?.range
        #expect(emph == Pos(line: 1, column: 1)..<Pos(line: 2, column: 3))       // "*a\nb*"
        #expect(bText == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))      // "b" on line 2
    }
}
