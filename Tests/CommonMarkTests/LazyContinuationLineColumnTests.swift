/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A lazy continuation line's text has the source range of its own bytes, which start at column 1 rather than at the
/// container's content column.
@Suite("Lazy continuation line columns")
struct LazyContinuationLineColumnTests {

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

    @Test("a middle lazy continuation line in a list item starts at column 1")
    func middleLineInListItem() throws {
        let texts = textRanges("- e\nc\ng", options: Self.specOptions)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c"
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "g"
    }

    @Test("the last lazy continuation line in a list item starts at column 1")
    func lastLineInListItem() throws {
        let texts = textRanges("- e\nc", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "e"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "c"
    }

    @Test("a lazy continuation line in a block quote starts at column 1")
    func lineInBlockQuote() throws {
        let texts = textRanges("> a\nbc\n", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 1, column: 3)..<Pos(line: 1, column: 4))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 3))   // "bc"
    }
}
