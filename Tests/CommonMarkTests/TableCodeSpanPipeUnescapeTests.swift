/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a table interrupts a paragraph, the lines before the header row form an ordinary paragraph (Paragraphs).
/// Only a cell's content unescapes `\|` (Tables (extension)), so a code span in those lines keeps its backslash
/// escapes literal (Code spans).
@Suite("Escaped pipe in a code span of a table's preceding paragraph")
struct TableCodeSpanPipeUnescapeTests {

    /// The literal content of the first `.codeInline` node anywhere in the document (depth-first, pre-order),
    /// plus whether the document contains a `.table` node.
    private func firstCodeSpanAndTable(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> (codeSpan: String?, hasTable: Bool) {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var acc = Walk(codeSpan: nil, hasTable: false)
            walk(doc.root, &acc)
            return (acc.codeSpan, acc.hasTable)
        }
    }

    @Test("code span in a table's preceding paragraph keeps its escaped pipe (backtick header)")
    func precedingParagraphCodeSpanKeepsEscapedPipe() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`\\|`\n`\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\|")
    }

    @Test("code span in a table's preceding paragraph keeps its escaped pipe (backslash header)")
    func precedingParagraphCodeSpanKeepsEscapedPipeBackslashHeader() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`\\|`\n\\\n-|", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\|")
    }

    @Test("code span in a block-quote table's preceding paragraph keeps its escaped pipe")
    func precedingParagraphCodeSpanKeepsEscapedPipeInBlockQuote() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("> `\\|`\n> `\n> |-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form inside the block quote")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\|")
    }

    @Test("code span in a tab-continuation table's preceding paragraph keeps its escaped pipe")
    func precedingParagraphCodeSpanKeepsEscapedPipeWithTabContinuation() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`\\|`\n\tx\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\|")
    }

    @Test("code span with no table keeps its escaped pipe")
    func standaloneCodeSpanKeepsEscapedPipe() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`\\|`", options: [.tables])
        try #require(!hasTable, "fixture: expected no table to form")
        try #require(codeSpan != nil, "fixture: expected a code span")
        #expect(codeSpan == "\\|")
    }

    @Test("preceding-paragraph code span keeps a non-pipe backslash escape")
    func precedingParagraphCodeSpanKeepsNonPipeEscape() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`\\!`\n`\n|-", options: [.tables])
        try #require(hasTable, "fixture: expected a table to form")
        try #require(codeSpan != nil, "fixture: expected a code span in the preceding paragraph")
        #expect(codeSpan == "\\!")
    }

    @Test("plain code span with an unescaped pipe is unaffected")
    func plainCodeSpanWithPipeUnaffected() throws {
        let (codeSpan, hasTable) = firstCodeSpanAndTable("`x|y`", options: [.tables])
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
