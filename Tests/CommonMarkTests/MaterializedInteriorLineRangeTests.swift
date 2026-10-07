/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A paragraph that could be a table or begin with a link reference definition, footnote definition or
/// checkbox has its content materialized into the arena. When it turns out to be a plain paragraph, each
/// inline's source range lies on its own source line, as for unmaterialized content.
@Suite("Source ranges of inlines on later lines of a materialized paragraph")
struct MaterializedInteriorLineRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    // `.tables` makes a paragraph containing a `|` a table candidate, which materializes its content.
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .tables, .strikethrough, .tasklist, .tableSpans]

    private func ranges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out
    }

    @Test("A pipe on an interior line spans 2:1-2:2")
    func interiorLinePipe() throws {
        let texts = ranges("t\n|\n b", options: Self.options).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "t"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "|" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 3))   // "b"
    }

    /// A `|` on line 1 makes the paragraph a table candidate; it has no delimiter row, so it stays a paragraph.
    @Test("An interior line after a first-line pipe spans 2:1-2:4")
    func interiorLineAfterFirstLinePipe() throws {
        let texts = ranges("|foo\nbar\n baz", options: Self.options).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 5))   // "|foo"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))   // "bar" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 5))   // "baz"
    }

}
