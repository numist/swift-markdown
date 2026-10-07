/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A code span spanning lines whose opening backtick string is on a lazy continuation line starts at that
/// backtick's own column.
@Suite("Multi-line code span opening on a lazy continuation line")
struct CodeSpanLazyContinuationRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    /// The source ranges of every `.codeInline` node, in document order.
    private func codeSpanRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter {
            if case .codeInline = $0.kind { return true }
            return false
        }.map(\.range)
    }

    @Test("code span opening on a block quote lazy continuation line is @2:1-3:2")
    func blockQuoteLazy() throws {
        let spans = codeSpanRanges("> o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    @Test("three-line code span on block quote lazy continuation lines is @2:1-4:2")
    func threeLineBlockQuoteLazy() throws {
        let spans = codeSpanRanges("> o\n`\nx\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 4, column: 2))
    }

    @Test("code span opening on a list item lazy continuation line is @2:1-3:2")
    func listItemLazy() throws {
        let spans = codeSpanRanges("- o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    @Test("code span opening after `> ` and closing on a lazy continuation line is @2:3-3:2")
    func matchedThenLazy() throws {
        let spans = codeSpanRanges("> o\n> `\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 3, column: 2))
    }

    @Test("top-level multi-line code span is @2:1-3:2")
    func topLevel() throws {
        let spans = codeSpanRanges("o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }
}
