/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark's GFM table extension unescapes `\|` → `|` over a table's raw text BEFORE inline parsing, via
/// `unescape_pipes` (`extensions/table.c`). That function has exactly two call sites, both reached only
/// once a table opens: `row_from_string` (each cell's text) and `try_inserting_table_header_paragraph`
/// (the text that precedes the header row, split off into its own paragraph). Because the unescape runs
/// over the raw bytes, it affects the content that later becomes a code span on those lines — so a
/// `` `\|` `` code span sitting in a table's preceding-paragraph text ends up with content `|`, even
/// though code spans normally keep backslash escapes literal.
///
/// The rewrite unescaped pipes only in the split cell text (finding #123), not in the preceding-paragraph
/// text, so a code span there kept its `\|`. This is the code-span facet of the same mechanism. GFM tables
/// are defined by cmark, so this is unconditional (NOT gated on `.cmarkBugCompatibility`).
@Suite("Table preceding-paragraph code-span pipe unescaping")
struct TableCodeSpanPipeUnescapeTests {

    /// The literal content of the first `.codeInline` node anywhere in the document (depth-first, pre-order),
    /// plus whether the document contains a `.table` node.
    private func firstCodeSpanAndTable(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) throws -> (codeSpan: String?, hasTable: Bool) {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var acc = Walk(codeSpan: nil, hasTable: false)
            walk(doc.root, &acc)
            return (acc.codeSpan, acc.hasTable)
        }
    }

    /// The finding (first fuzzer hit): `` `\|` `` on the first line, then a one-column table (`` ` ``
    /// header, `|-` delimiter). cmark splits the first line into a preceding paragraph and unescapes its
    /// `\|` → `|` before inline parsing, so the paragraph's code span reads `|`.
    @Test("code span in a table's preceding paragraph unescapes its pipe (backtick header)")
    func precedingParagraphCodeSpanUnescapesPipe() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`\\|`\n`\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "|")
    }

    /// The finding (second fuzzer hit): `` `\|` `` on the first line, then a one-column table (`\` header,
    /// `-|` delimiter). Same divergence via the same preceding-paragraph split.
    @Test("code span in a table's preceding paragraph unescapes its pipe (backslash header)")
    func precedingParagraphCodeSpanUnescapesPipeBackslashHeader() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`\\|`\n\\\n-|", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "|")
    }

    /// The nested (block-quote) form of the same class: the preceding paragraph arrives as a non-contiguous
    /// segment list, split by `splitSegmentHeader` rather than the contiguous `detectPendingTable` path.
    /// cmark opens the table inside the block quote and unescapes the preceding paragraph's `\|` just the
    /// same, so the code span reads `|`.
    @Test("code span in a block-quote table's preceding paragraph unescapes its pipe")
    func precedingParagraphCodeSpanUnescapesPipeInBlockQuote() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("> `\\|`\n> `\n> |-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form inside the block quote")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "|")
    }

    /// A multi-line paragraph whose continuation line carries a leading tab is accumulated non-contiguously
    /// with positions off, so the preceding-paragraph split goes through the materialized/segment (not the
    /// source-contiguous) path. The `\|` on the first line still unescapes to `|`.
    @Test("code span in a tab-continuation table's preceding paragraph unescapes its pipe")
    func precedingParagraphCodeSpanUnescapesPipeWithTabContinuation() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`\\|`\n\tx\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "|")
    }

    /// Control: `` `\|` `` with NO table nearby. `unescape_pipes` runs only once a table opens, so a
    /// standalone code span is never touched and keeps its `\|` (code spans do not process backslash
    /// escapes). Guards against over-unescaping outside table context.
    @Test("code span with no table keeps its escaped pipe")
    func standaloneCodeSpanKeepsEscapedPipe() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`\\|`", options: [.tables])
        try #require(!hasTable, "fixture: expected no table to form")
        try #require(codeSpan != nil, "fixture: expected a code span")
        #expect(codeSpan == "\\|")
    }

    /// Control: only `\|` is unescaped, never other backslash escapes. A `` `\!` `` code span in a table's
    /// preceding paragraph keeps its `\!` — `unescape_pipes` drops only the backslash directly before a
    /// `|`, and code spans do not otherwise process escapes.
    @Test("preceding-paragraph code span keeps a non-pipe backslash escape")
    func precedingParagraphCodeSpanKeepsNonPipeEscape() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`\\!`\n`\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\!")
    }

    /// Control: a plain code span with an UNescaped pipe (`` `x|y` ``) is unaffected — no backslash to drop.
    @Test("plain code span with an unescaped pipe is unaffected")
    func plainCodeSpanWithPipeUnaffected() throws {
        let (codeSpan, hasTable) = try firstCodeSpanAndTable("`x|y`", options: [.tables])
        try #require(!hasTable, "fixture: expected no table to form")
        try #require(codeSpan != nil, "fixture: expected a code span")
        #expect(codeSpan == "x|y")
    }
}

/// Depth-first pre-order accumulator for `walk`. `codeSpan` latches the first `.codeInline` literal.
private struct Walk {
    var codeSpan: String?
    var hasTable: Bool
}

// File-scope + `borrowing MarkdownNode` because a `MarkdownNode` is `~Escapable` and can't be captured by
// an instance-method closure.
private func walk(_ node: borrowing MarkdownNode, _ acc: inout Walk) {
    if node.kind == .table {
        acc.hasTable = true
    }
    if acc.codeSpan == nil, case .codeInline = node.kind {
        acc.codeSpan = node.literal()
    }
    node.children.forEach { child in
        walk(child, &acc)
    }
}
