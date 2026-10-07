/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position stamping for a paragraph continuation line under the Quirk-E re-indent.
///
/// `- e\nc`: the list item's paragraph content column is 3 (the `- ` marker is 2 columns). Flag-ON,
/// cmark re-indents the continuation line `c` to the block content column 3 and reports it at `@2:3-2:4`.
/// The rewrite stamps the re-indented byte offsets too, but no range may run past the end of the
/// physical line its content is on: `c`'s line ends at column 2, so its range is cut off there and
/// collapses to `@2:2-2:2`.
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
    ) -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter { $0.kind == .text }.map(\.range)
    }

    /// The deliverable (flag-OFF, spec-correct default): the middle continuation line `c` keeps its
    /// TRUE physical position `@2:1-2:2`.
    @Test("flag-OFF: 1-char middle continuation keeps its true column")
    func specMiddleContinuation() throws {
        let texts = textRanges("- e\nc\ng", options: Self.specOptions)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c" true column
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "g"
    }

    /// A 1-char continuation as the LAST line: its re-indented column 3 lies past the line's end at
    /// column 2 (the source's end), so the range is cut off there. cmark-gfm reports `@2:3-2:4`.
    @Test("flag-ON: 1-char last continuation is cut off at its line's end, @2:2-2:2")
    func quirkLastContinuation() throws {
        let texts = textRanges("- e\nc", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[1] == Pos(line: 2, column: 2)..<Pos(line: 2, column: 2))   // "c"
    }

    /// A 1-char continuation in the MIDDLE: its re-indented column 3 is past its line's newline at
    /// column 2, so the range is cut off there rather than running onto line 3. cmark-gfm reports
    /// `@2:3-2:4` for `c` and `@3:3-3:4` for `g`.
    @Test("flag-ON: 1-char middle continuation is cut off at its line's end, @2:2-2:2")
    func quirkMiddleContinuation() throws {
        let texts = textRanges("- e\nc\ng", options: Self.quirkOptions)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 2)..<Pos(line: 2, column: 2))   // "c"
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 2))   // "g"
    }

    /// A 2-char lazy continuation of a block quote: cmark re-indents `bc` to column 3, its line's
    /// newline, so the range starts there and its end, column 5, is cut off to column 3. cmark-gfm
    /// reports `@2:3-2:5`.
    @Test("flag-ON: a re-indented lazy line's end is cut off at its newline")
    func quirkLazyContinuationEnd() throws {
        let texts = textRanges("> a\nbc\n", options: Self.quirkOptions)
        try #require(texts.count == 2)
        #expect(texts[1] == Pos(line: 2, column: 3)..<Pos(line: 2, column: 3))   // "bc"
    }

    /// Twin of `quirkLastContinuation`: the deliverable (flag-OFF) keeps the last continuation line `c`
    /// at its TRUE physical position `@2:1-2:2`. The flag-ON re-indent (`@2:3`) is a real active quirk
    /// for this shape, so this twin pins the spec-correct default it diverges from.
    @Test("flag-OFF: 1-char last continuation keeps its true column @2:1-2:2")
    func specLastContinuation() throws {
        let texts = textRanges("- e\nc", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c" true column
    }

    /// A lazy continuation line's text keeps the source position of its own bytes (`bc` at `@2:1-2:3`), whereas
    /// cmark-gfm re-indents it to the block quote's content column 3.
    @Test("flag-OFF: a lazy continuation line keeps its true columns @2:1-2:3")
    func specLazyContinuationEnd() throws {
        let texts = textRanges("> a\nbc\n", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))   // "bc" true columns
    }
}
