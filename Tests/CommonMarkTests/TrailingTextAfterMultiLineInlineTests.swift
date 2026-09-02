/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Coverage for source-position stamping of a plain-text run that FOLLOWS a multi-line inline (code span
/// or emphasis) on the last content line of a re-indented multi-segment paragraph - a blockquote or
/// list-item paragraph whose lazy continuations are joined as a segment list.
///
/// Flag-OFF (the shipped default) is spec-correct: the trailing text run carries its true byte-projected
/// position on its own physical line.
@Suite("Trailing text after a multi-line inline in a re-indented container paragraph")
struct TrailingTextAfterMultiLineInlineTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func textRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter { $0.kind == .text }.map(\.range)
    }

    /// The deliverable (flag-OFF, spec-correct default): the trailing `o` after a multi-line code span in a
    /// blockquote paragraph carries its true byte-projected position on its own physical line (`@2:2-2:3`).
    @Test("flag-OFF: text after a multi-line code span is stamped on its own line")
    func specTrailingTextStamped() throws {
        let texts = try textRanges("> `\n`o\nx", options: Self.specOptions)
        try #require(texts.count == 2)
        #expect(texts[0] == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))   // "o"
        #expect(texts[1] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "x"
    }
}
