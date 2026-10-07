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
/// `- e\nc`: the list item's paragraph content column is 3 (the `- ` marker is 2 columns).
///
/// Flag-OFF (the shipped default) is spec-correct: every continuation line keeps its TRUE physical
/// column, so `c` is `@2:1-2:2`.
@Suite("Continuation re-indent overshooting its own physical line")
struct ContinuationReindentOvershootRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

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

    /// The deliverable (flag-OFF) keeps the last continuation line `c`
    /// at its TRUE physical position `@2:1-2:2`.
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
