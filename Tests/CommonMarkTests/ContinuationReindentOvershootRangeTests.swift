/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position stamping for a paragraph continuation line whose Quirk-E re-indent shift
/// EXCEEDS the line's own content width, so the re-indented source offset overshoots past the
/// line's byte extent onto a LATER physical line.
///
/// `- e\nc\ng`: the list item's paragraph content column is 3 (the `- ` marker is 2 columns).
/// The 1-character middle continuation line `c` sits physically at column 1; cmark re-indents it to
/// the block content column 3 and reports it at `@2:3` even though column 3 is past line 2's only
/// byte. The rewrite stamps source positions as byte offsets, and the re-indented offset for `c`
/// (line-2 start + content indent 2) lands on line 3's `g` byte - so a naive byte projection
/// overshoots to `@3:1`. The flag-ON overshoot correction must anchor `c`'s LINE on its physical
/// byte (line 2) while taking the re-indented COLUMN from the mapped offset, giving `@2:3-2:4`.
///
/// A 2-character middle line (`cc`) or a last line (`c` with no following line) does NOT overshoot
/// onto a later physical line, so those keep the existing behavior; they are guardrails here.
///
/// Flag-OFF (the shipped default) is spec-correct: every continuation line keeps its TRUE physical
/// column, so `c` is `@2:1-2:2`. (Regression for the differential-fuzzer `reindentover-*` pairs.)
@Suite("Continuation re-indent overshooting its own physical line")
struct ContinuationReindentOvershootRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    private func textRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter { $0.kind == .text }.map(\.range)
    }

    /// The deliverable (flag-OFF, spec-correct default): the middle continuation line `c` keeps its
    /// TRUE physical position `@2:1-2:2`.
    @Test("flag-OFF: 1-char middle continuation keeps its true column")
    func specMiddleContinuation() throws {
        let texts = try textRanges("- e\nc\ng", options: Self.specOptions)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c" true column
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "g"
    }

    /// Flag-ON (differential-fuzzer configuration). cmark re-indents the 1-char middle line `c` to
    /// the block content column 3 and keeps it on its own physical line 2: `@2:3-2:4` (NOT the
    /// byte-projected overshoot `@3:1`).
    @Test("flag-ON: 1-char middle continuation re-indents to @2:3 on its own line")
    func quirkMiddleContinuation() throws {
        let texts = try textRanges("- e\nc\ng", options: Self.quirkOptions)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 4))   // "c" re-indented, own line
        #expect(texts[2] == Pos(line: 3, column: 3)..<Pos(line: 3, column: 4))   // "g" re-indented (last line)
    }

    /// Guardrail: a 2-character middle continuation line does NOT overshoot (the re-indented column
    /// still has a byte on its own physical line), so it keeps the existing correction `@2:3-2:5`.
    @Test("flag-ON: 2-char middle continuation is @2:3-2:5")
    func quirkWideMiddleContinuation() throws {
        let texts = try textRanges("- e\ncc\ng", options: Self.quirkOptions)
        try #require(texts.count == 3)
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 5))   // "cc"
    }

    /// Guardrail: a 1-char continuation as the LAST line has no following physical line to overshoot
    /// onto, so its byte projection already lands correctly at `@2:3-2:4`.
    @Test("flag-ON: 1-char last continuation is @2:3-2:4")
    func quirkLastContinuation() throws {
        let texts = try textRanges("- e\nc", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 4))   // "c"
    }
}
