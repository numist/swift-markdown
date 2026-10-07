/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source ranges of inlines on the second and later lines of a multi-line segment. Adjacent paragraph
/// lines with no stripped indentation share one segment; a later indented line starts another. Each
/// inline's source range lies on its own line.
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

    @Test("interior line b is stamped @2:1-2:2")
    func interiorLineStamped() throws {
        let texts = ranges("a\nb\n c", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 3)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b" (interior line)
        #expect(texts[2] == Pos(line: 3, column: 2)..<Pos(line: 3, column: 3))   // "c"
    }

    @Test("four-line paragraph keeps the final indented line's column")
    func fourLineFinalIndentedLine() throws {
        let texts = ranges("a\nb\nc\n d", options: Self.specOptions).filter { $0.kind == .text }.map(\.range)
        try #require(texts.count == 4)
        #expect(texts[0] == Pos(line: 1, column: 1)..<Pos(line: 1, column: 2))   // "a"
        #expect(texts[1] == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))   // "b"
        #expect(texts[2] == Pos(line: 3, column: 1)..<Pos(line: 3, column: 2))   // "c"
        #expect(texts[3] == Pos(line: 4, column: 2)..<Pos(line: 4, column: 3))   // "d"
    }

    @Test("single-line emphasis on an interior contiguous line is stamped on its own line")
    func interiorLineEmphasis() {
        let all = ranges("a\n*b*\n c", options: Self.specOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let innerText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 2)) }?.range
        #expect(emph == Pos(line: 2, column: 1)..<Pos(line: 2, column: 4))       // "*b*"
        #expect(innerText == Pos(line: 2, column: 2)..<Pos(line: 2, column: 3))  // "b"
    }

    @Test("multi-line emphasis on a contiguous segment keeps its closer on line 2")
    func multiLineEmphasis() {
        let all = ranges("*a\nb*\n c", options: Self.specOptions)
        let emph = all.first { $0.kind == .emphasis }?.range
        let bText = all.first { $0.kind == .text && ($0.range?.lowerBound == Pos(line: 2, column: 1)) }?.range
        #expect(emph == Pos(line: 1, column: 1)..<Pos(line: 2, column: 3))       // "*a\nb*"
        #expect(bText == Pos(line: 2, column: 1)..<Pos(line: 2, column: 2))      // "b" on line 2
    }
}
