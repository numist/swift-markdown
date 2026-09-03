/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position stamping for a MULTI-LINE code span whose OPENER sits on a block-quote / list
/// LAZY continuation line (no container prefix on the line).
///
/// Flag-OFF (the shipped default) is spec-correct: no re-indent happens, so the code span keeps its
/// TRUE physical column (opener at line 2 column 1) and never overshoots. These are the deliverable
/// guardrails.
@Suite("Multi-line code span opening on a lazy continuation")
struct CodeSpanLazyContinuationRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]
    private static let quirkOptions: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    /// The source ranges of every `.codeInline` node, in document order.
    private func codeSpanRanges(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> [Range<Pos>?] {
        var out: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            dfsRanges(doc.root, into: &out)
        }
        return out.filter {
            if case .codeInline = $0.kind { return true }
            return false
        }.map(\.range)
    }

    // MARK: - Block-quote lazy continuation (the minimal reproducer)

    /// Flag-OFF (deliverable, spec-correct): no re-indent, so the opener keeps its true physical
    /// column 1 -> `@2:1-3:2`. No overshoot.
    @Test("flag-OFF: code span opening on a bq lazy line keeps its true column @2:1-3:2")
    func specBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    // MARK: - Three physical lines spanned by one code span

    /// Flag-OFF (deliverable): true physical column 1 -> `@2:1-4:2`.
    @Test("flag-OFF: 3-line code span on bq lazy continuations is @2:1-4:2")
    func specThreeLineBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\nx\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 4, column: 2))
    }

    // MARK: - List-item lazy continuation (not just block quote)

    /// Flag-OFF (deliverable): true physical column 1 -> `@2:1-3:2`.
    @Test("flag-OFF: code span on a list-item lazy line keeps its true column @2:1-3:2")
    func specListItemLazy() throws {
        let spans = try codeSpanRanges("- o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    // MARK: - Mixed matched-then-lazy continuation

    /// Flag-OFF (deliverable): a code span whose opener is on a MATCHED continuation (`> ` present, so
    /// its content already sits at the block column) and whose closer is on a following LAZY line stamps
    /// `@2:3-3:2` — the matched opener sits at its true physical column 3 and the closer byte-projects to
    /// line 3.
    @Test("matched-then-lazy code span is @2:3-3:2")
    func matchedThenLazy() throws {
        let spans = try codeSpanRanges("> o\n> `\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 3, column: 2))
    }

    // MARK: - Top-level control (no re-indent, no overshoot on either flag)

    /// Guardrail: a top-level multi-line code span has block content column 1, so there is no
    /// re-indent and both flags agree at `@2:1-3:2`.
    @Test("top-level multi-line code span is @2:1-3:2 both flags")
    func topLevelControl() throws {
        for options in [Self.quirkOptions, Self.specOptions] {
            let spans = try codeSpanRanges("o\n`\n`", options: options)
            try #require(spans.count == 1)
            #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
        }
    }
}
