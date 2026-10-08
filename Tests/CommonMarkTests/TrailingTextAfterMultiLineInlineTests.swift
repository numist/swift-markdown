/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A text run that follows an inline spanning a line ending, in a block quote paragraph with lazy
/// continuation lines, has a source range on its own line.
@Suite("Trailing text after a multi-line inline in a block quote paragraph")
struct TrailingTextAfterMultiLineInlineTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func textRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter { $0.kind == .text }.map(\.range)
    }

    @Test("text after a multi-line code span has a source range on its own line")
    func trailingTextRangeOnItsLine() throws {
        let texts = textRanges("> `\n`o\nx", options: Self.options)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))   // "o"
        #expect(texts[1] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "x"
    }
}
