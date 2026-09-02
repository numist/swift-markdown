/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source-position stamping for a MULTI-LINE code span whose OPENER sits on a block-quote / list
/// LAZY continuation line (no container prefix on the line), where the Quirk-E re-indent shift
/// exceeds the opener line's content width.
///
/// `> o\n`` \n`` `` (a blockquote paragraph `o`, then two lazy `` ` `` lines forming a code span):
/// cmark re-indents each lazy continuation to the block content column 3, keeps the code span on the
/// opener's PHYSICAL line 2, and reports `@2:3-3:2`. The rewrite maps the re-indented opener offset
/// to a byte, which - because line 2 holds only the single backtick - overshoots past line 2 onto
/// line 3; the byte projection then stamps the start `@3:1` and `stampCodeSpanEnd` derives its end
/// line from that overshot line, giving `@4:2` (a line that does not exist). The flag-ON correction
/// anchors the code span's LINE on the opener's physical byte (via `physicalOffset`) while taking the
/// re-indented COLUMN from the mapped source offset - the same Quirk-E overshoot anchor the text path
/// uses (see `InlineParser.stampInline` / `stampCodeSpanEnd`).
///
/// Flag-OFF (the shipped default) is spec-correct: no re-indent happens, so the code span keeps its
/// TRUE physical column (opener at line 2 column 1) and never overshoots. This pins the flag split:
/// the whole divergence rides the existing `.cmarkBugCompatibility` Quirk-E gate; the deliverable is
/// unchanged. (Regressions for the differential-fuzzer `bqcode-*` pairs.)
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

    /// Flag-ON: cmark re-bases the lazy continuation to the block content column 3 and keeps the code
    /// span on the opener's own physical line 2 -> `@2:3-3:2`.
    @Test("flag-ON: code span opening on a bq lazy line is @2:3-3:2")
    func quirkBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\n`", options: Self.quirkOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 3, column: 2))
    }

    /// Flag-OFF (deliverable, spec-correct): no re-indent, so the opener keeps its true physical
    /// column 1 -> `@2:1-3:2`. No overshoot.
    @Test("flag-OFF: code span opening on a bq lazy line keeps its true column @2:1-3:2")
    func specBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    // MARK: - Three physical lines spanned by one code span

    /// Flag-ON: opener on lazy line 2, content on line 3, closer on line 4 -> `@2:3-4:2`.
    @Test("flag-ON: 3-line code span on bq lazy continuations is @2:3-4:2")
    func quirkThreeLineBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\nx\n`", options: Self.quirkOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 4, column: 2))
    }

    /// Flag-OFF (deliverable): true physical column 1 -> `@2:1-4:2`.
    @Test("flag-OFF: 3-line code span on bq lazy continuations is @2:1-4:2")
    func specThreeLineBlockQuoteLazy() throws {
        let spans = try codeSpanRanges("> o\n`\nx\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 4, column: 2))
    }

    // MARK: - List-item lazy continuation (not just block quote)

    /// Flag-ON: a list item's lazy continuation re-bases to the item content column 3 -> `@2:3-3:2`.
    @Test("flag-ON: code span on a list-item lazy line is @2:3-3:2")
    func quirkListItemLazy() throws {
        let spans = try codeSpanRanges("- o\n`\n`", options: Self.quirkOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 3, column: 2))
    }

    /// Flag-OFF (deliverable): true physical column 1 -> `@2:1-3:2`.
    @Test("flag-OFF: code span on a list-item lazy line keeps its true column @2:1-3:2")
    func specListItemLazy() throws {
        let spans = try codeSpanRanges("- o\n`\n`", options: Self.specOptions)
        try #require(spans.count == 1)
        #expect(spans[0] == Pos(line: 2, column: 1)..<Pos(line: 3, column: 2))
    }

    // MARK: - Mixed matched-then-lazy continuation

    /// A code span whose opener is on a MATCHED continuation (`> ` present, content already at the
    /// block column, so no re-indent overshoot) and whose closer is on a following LAZY line. Both
    /// flag-ON and flag-OFF stamp `@2:3-3:2` because the matched opener sits at its true physical
    /// column 3. This guards that the fix does not disturb a matched opener.
    @Test("matched-then-lazy code span is @2:3-3:2 both flags")
    func matchedThenLazy() throws {
        for options in [Self.quirkOptions, Self.specOptions] {
            let spans = try codeSpanRanges("> o\n> `\n`", options: options)
            try #require(spans.count == 1)
            #expect(spans[0] == Pos(line: 2, column: 3)..<Pos(line: 3, column: 2))
        }
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
