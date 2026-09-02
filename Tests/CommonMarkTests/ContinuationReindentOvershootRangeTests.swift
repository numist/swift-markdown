/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position stamping for a paragraph continuation line under the Quirk-E re-indent.
///
/// `- e\nc`: the list item's paragraph content column is 3 (the `- ` marker is 2 columns). Flag-ON,
/// cmark re-indents the continuation line `c` to the block content column 3 and reports it at `@2:3`.
/// The rewrite stamps source positions as byte offsets; where the re-indented offset stays on the
/// line's own physical bytes (a last line with no following line to spill onto) the byte projection
/// lands correctly at `@2:3-2:4`.
///
/// Flag-OFF (the shipped default) is spec-correct: every continuation line keeps its TRUE physical
/// column, so `c` is `@2:1-2:2`.
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

    /// Guardrail: a 1-char continuation as the LAST line has no following physical line to overshoot
    /// onto, so its byte projection already lands correctly at `@2:3-2:4`.
    @Test("flag-ON: 1-char last continuation is @2:3-2:4")
    func quirkLastContinuation() throws {
        let texts = try textRanges("- e\nc", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 4))   // "c"
    }

    /// Twin of `quirkLastContinuation`: the deliverable (flag-OFF) keeps the last continuation line `c`
    /// at its TRUE physical position `@2:1-2:2`. The flag-ON re-indent (`@2:3`) is a real active quirk
    /// for this shape, so this twin pins the spec-correct default it diverges from.
    @Test("flag-OFF: 1-char last continuation keeps its true column @2:1-2:2")
    func specLastContinuation() throws {
        let texts = try textRanges("- e\nc", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c" true column
    }
}
