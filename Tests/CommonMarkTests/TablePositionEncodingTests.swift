/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Table and tab-indented source positions — Unicode encodings")
struct TablePositionEncodingTests {

    typealias Pos = MarkdownNode.SourcePosition

    static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func r(_ sl: Int, _ sc: Int, _ el: Int, _ ec: Int) -> Range<Pos> {
        Pos(line: sl, column: sc)..<Pos(line: el, column: ec)
    }

    private func nodes(_ source: String) -> [EncNode] {
        MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> [EncNode] in
            var out: [EncNode] = []
            dfsEncNodes(doc.root, into: &out)
            return out
        }
    }

    @Test("multi-column: multibyte at a body cell's start counts its bytes")
    func bodyCellMultibyteStart() throws {
        let rows = firstTableRows("a|b\n-|-\n\u{E9}x|y", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row, got \(rows.count)")
        let body = rows[1]
        try #require(body.cells.count == 2, "fixture: two body cells, got \(body.cells.count)")
        try #require(body.cells[0].text == "\u{E9}x" && body.cells[1].text == "y", "fixture: cell literals")
        #expect(body.range == r(3, 1, 3, 6))
        #expect(body.cells[0].range == r(3, 1, 3, 4))
        #expect(body.cells[0].textRange == r(3, 1, 3, 4))
        #expect(body.cells[1].range == r(3, 5, 3, 6))
        #expect(body.cells[1].textRange == r(3, 5, 3, 6))
    }

    @Test("multi-column: a padded multibyte cell covers just its content bytes")
    func paddedMultibyteCells() throws {
        let rows = firstTableRows("a|b\n-|-\n| \u{E9} | \u{1F600} |  ", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "\u{E9}" && body.cells[1].text == "\u{1F600}", "fixture: cell literals")
        #expect(body.cells[0].range == r(3, 3, 3, 5))
        #expect(body.cells[0].textRange == r(3, 3, 3, 5))
        #expect(body.cells[1].range == r(3, 8, 3, 12))
        #expect(body.cells[1].textRange == r(3, 8, 3, 12))
        #expect(body.range == r(3, 1, 3, 14))
    }

    @Test("multi-column: a 3-byte cell spans three byte-columns")
    func bodyCellThreeByte() throws {
        let rows = firstTableRows("a|b\n-|-\nx|\u{20AC}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{20AC}", "fixture: `€` cell literal")
        #expect(body.cells[0].range == r(3, 1, 3, 2))
        #expect(body.cells[1].range == r(3, 3, 3, 6))
        #expect(body.cells[1].textRange == r(3, 3, 3, 6))
        #expect(body.range == r(3, 1, 3, 6))
    }

    @Test("multi-column: a 4-byte emoji cell spans four byte-columns")
    func bodyCellEmoji() throws {
        let rows = firstTableRows("a|b\n-|-\nx|\u{1F600}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{1F600}", "fixture: emoji cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 7))
        #expect(body.cells[1].textRange == r(3, 3, 3, 7))
        #expect(body.range == r(3, 1, 3, 7))
    }

    @Test("multi-column: a combining sequence in a cell counts its bytes")
    func bodyCellCombining() throws {
        let rows = firstTableRows("a|b\n-|-\ne\u{301}x|y", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "e\u{301}x", "fixture: combining cell literal")
        #expect(body.cells[0].range == r(3, 1, 3, 5))
        #expect(body.cells[0].textRange == r(3, 1, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))
        #expect(body.range == r(3, 1, 3, 7))
    }

    @Test("multi-column: a literal U+FFFD cell counts three byte-columns")
    func bodyCellReplacementChar() throws {
        let rows = firstTableRows("a|b\n-|-\nx|\u{FFFD}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[1].text == "\u{FFFD}", "fixture: U+FFFD cell literal")
        #expect(body.cells[1].range == r(3, 3, 3, 6))
        #expect(body.cells[1].textRange == r(3, 3, 3, 6))
    }

    @Test("multi-column: multibyte in the middle column shifts the right column by its byte width")
    func middleColumnMultibyte() throws {
        let rows = firstTableRows("a|b|c\n-|-|-\nx|\u{E9}|z", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 3 && body.cells.map(\.text) == ["x", "\u{E9}", "z"], "fixture: three cells")
        #expect(body.cells[0].range == r(3, 1, 3, 2))
        #expect(body.cells[1].range == r(3, 3, 3, 5))
        #expect(body.cells[1].textRange == r(3, 3, 3, 5))
        #expect(body.cells[2].range == r(3, 6, 3, 7))
        #expect(body.range == r(3, 1, 3, 7))
    }

    @Test("multi-column: multibyte in the header widens the header ranges")
    func headerMultibyte() throws {
        let rows = firstTableRows("\u{20AC}x|y\n-|-\nc|d", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let head = rows[0]
        try #require(head.isHeader && head.cells.count == 2 && head.cells[0].text == "\u{20AC}x", "fixture: header cells")
        #expect(head.range == r(1, 1, 1, 7))
        #expect(head.cells[0].range == r(1, 1, 1, 5))
        #expect(head.cells[0].textRange == r(1, 1, 1, 5))
        #expect(head.cells[1].range == r(1, 6, 1, 7))
        #expect(rows[1].cells.map(\.range) == [r(3, 1, 3, 2), r(3, 3, 3, 4)])
    }

    @Test("multi-column: independent multibyte in header and body")
    func headerAndBodyMultibyte() throws {
        let rows = firstTableRows("\u{E9}|b\n-|-\nc|\u{20AC}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[0].cells.map(\.text) == ["\u{E9}", "b"] && rows[1].cells.map(\.text) == ["c", "\u{20AC}"],
                     "fixture: cell literals")
        #expect(rows[0].range == r(1, 1, 1, 5))
        #expect(rows[0].cells[0].range == r(1, 1, 1, 3))
        #expect(rows[0].cells[1].range == r(1, 4, 1, 5))
        #expect(rows[1].range == r(3, 1, 3, 6))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 2))
        #expect(rows[1].cells[1].range == r(3, 3, 3, 6))
        #expect(rows[1].cells[1].textRange == r(3, 3, 3, 6))
    }

    @Test("single-column: multibyte header and body cells")
    func singleColumnMultibyte() throws {
        let rows = firstTableRows("\u{E9}\n|-\n\u{20AC}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row, got \(rows.count)")
        try #require(rows[0].cells.count == 1 && rows[1].cells.count == 1, "fixture: one column")
        try #require(rows[0].cells[0].text == "\u{E9}" && rows[1].cells[0].text == "\u{20AC}", "fixture: literals")
        #expect(rows[0].range == r(1, 1, 1, 3))
        #expect(rows[0].cells[0].range == r(1, 1, 1, 3))
        #expect(rows[0].cells[0].textRange == r(1, 1, 1, 3))
        #expect(rows[1].range == r(3, 1, 3, 4))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 4))
        #expect(rows[1].cells[0].textRange == r(3, 1, 3, 4))
    }

    @Test("single-column: leading-pipe body cell with multibyte")
    func singleColumnLeadingPipeMultibyte() throws {
        let rows = firstTableRows("a\n|-\n|\u{20AC}", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[1].cells.count == 1 && rows[1].cells[0].text == "\u{20AC}", "fixture: `€` body cell")
        #expect(rows[1].range == r(3, 1, 3, 5))
        #expect(rows[1].cells[0].range == r(3, 2, 3, 5))
        #expect(rows[1].cells[0].textRange == r(3, 2, 3, 5))
    }

    @Test("escaped pipe: \\|-escaped header cell counts the bytes around the pipe")
    func escapedPipeHeaderCellMultibyte() throws {
        let rows = firstTableRows("\u{E9}\\|\u{20AC}|c\n-|-", options: Self.opts)
        try #require(rows.count == 1, "fixture: header-only table, got \(rows.count) rows")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "\u{E9}|\u{20AC}" && head.cells[1].text == "c",
                     "fixture: escaped-pipe cell literal `é|€`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))
        #expect(head.cells[0].textRange == r(1, 1, 1, 8))
        #expect(head.cells[1].range == r(1, 9, 1, 10))
        #expect(head.cells[1].textRange == r(1, 9, 1, 10))
        #expect(head.range == r(1, 1, 1, 10))
    }

    @Test("escaped pipe: \\|-escaped header cell counts a 4-byte emoji")
    func escapedPipeHeaderCellEmoji() throws {
        let rows = firstTableRows("x\\|\u{1F600}|y\n-|-", options: Self.opts)
        try #require(rows.count == 1, "fixture: header-only table")
        let head = rows[0]
        try #require(head.cells.count == 2 && head.cells[0].text == "x|\u{1F600}" && head.cells[1].text == "y",
                     "fixture: escaped-pipe cell literal `x|😀`")
        #expect(head.cells[0].range == r(1, 1, 1, 8))
        #expect(head.cells[0].textRange == r(1, 1, 1, 8))
        #expect(head.cells[1].range == r(1, 9, 1, 10))
    }

    @Test("escaped pipe: \\|-escaped body cell counts the bytes around the pipe")
    func escapedPipeBodyCellMultibyte() throws {
        let rows = firstTableRows("a|b\n-|-\n\u{E9}\\|\u{20AC}|c", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2 && body.cells[0].text == "\u{E9}|\u{20AC}" && body.cells[1].text == "c",
                     "fixture: escaped-pipe body cell literal `é|€`")
        #expect(body.cells[0].range == r(3, 1, 3, 8))
        #expect(body.cells[0].textRange == r(3, 1, 3, 8))
        #expect(body.cells[1].range == r(3, 9, 3, 10))
        #expect(body.cells[1].textRange == r(3, 9, 3, 10))
        #expect(body.range == r(3, 1, 3, 10))
    }

    @Test("tab: list-item content after a tab maps back to its source byte column")
    func listItemContentAfterTab() throws {
        let nodes = nodes("-\t\u{E9}x")
        let para = nodes.first { $0.kind == .paragraph }
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x", "fixture: item paragraph text `éx`")
        #expect(para?.range == r(1, 3, 1, 6))
        #expect(text?.range == r(1, 3, 1, 6))
    }

    @Test("tab: indented code block, leading tab + multibyte body")
    func indentedCodeLeadingTab() throws {
        let nodes = nodes("\tcode\u{E9}")
        let code = nodes.first { if case .codeBlock = $0.kind { return true } else { return false } }
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`")
        #expect(code?.range == r(1, 2, 1, 8))
    }

    @Test("tab: indented code block, interior tab kept literally + multibyte")
    func indentedCodeInteriorTab() throws {
        let nodes = nodes("\tco\tde\u{E9}")
        let code = nodes.first { if case .codeBlock = $0.kind { return true } else { return false } }
        try #require(code?.literal == "co\tde\u{E9}\n", "fixture: code body keeps the interior tab")
        #expect(code?.range == r(1, 2, 1, 9))
    }

    @Test("tab: indented code block, excess leading tab becomes a body byte")
    func indentedCodeExcessTab() throws {
        let nodes = nodes("\t\tcode\u{E9}")
        let code = nodes.first { if case .codeBlock = $0.kind { return true } else { return false } }
        try #require(code?.literal == "\tcode\u{E9}\n", "fixture: body keeps the second (residual) tab")
        #expect(code?.range == r(1, 2, 1, 9))
    }

    @Test("tab: indented code block, spaces then a tab complete the indent")
    func indentedCodeSpacesThenTab() throws {
        let nodes = nodes("  \tcode\u{E9}")
        let code = nodes.first { if case .codeBlock = $0.kind { return true } else { return false } }
        try #require(code?.literal == "code\u{E9}\n", "fixture: code body `codeé`, no residual whitespace")
        #expect(code?.range == r(1, 4, 1, 10))
    }

    @Test("tab: list-item content after a tab, with an interior tab + multibyte")
    func listItemAfterTabInteriorTab() throws {
        let nodes = nodes("-\t\u{E9}x\ty")
        let text = nodes.first { $0.kind == .text }
        try #require(text?.literal == "\u{E9}x\ty", "fixture: item text keeps the interior tab")
        #expect(text?.range == r(1, 3, 1, 8))
    }

    @Test("an indented multibyte body row's cells start after its leading whitespace")
    func leadingWhitespaceBodyRowMultibyte() throws {
        let rows = firstTableRows("a|b\n-|-\n \u{E9}x|y", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        let body = rows[1]
        try #require(body.cells.count == 2, "fixture: two body cells")
        try #require(body.cells[0].text == "\u{E9}x" && body.cells[1].text == "y", "fixture: cell literals")
        #expect(body.range == r(3, 2, 3, 7))
        #expect(body.cells[0].range == r(3, 2, 3, 5))
        #expect(body.cells[0].textRange == r(3, 2, 3, 5))
        #expect(body.cells[1].range == r(3, 6, 3, 7))
    }

    @Test("an indented multibyte header row does not shift an unindented body row")
    func leadingWhitespaceHeaderMultibyte() throws {
        let rows = firstTableRows(" \u{E9}|b\n-|-\nx|y", options: Self.opts)
        try #require(rows.count == 2, "fixture: header + body row")
        try #require(rows[0].cells.count == 2 && rows[1].cells.count == 2, "fixture: two cells per row")
        try #require(rows[0].cells[0].text == "\u{E9}" && rows[1].cells.map(\.text) == ["x", "y"], "fixture: literals")
        #expect(rows[0].range == r(1, 2, 1, 6))
        #expect(rows[0].cells[0].range == r(1, 2, 1, 4))
        #expect(rows[0].cells[1].range == r(1, 5, 1, 6))
        #expect(rows[1].range == r(3, 1, 3, 4))
        #expect(rows[1].cells[0].range == r(3, 1, 3, 2))
        #expect(rows[1].cells[1].range == r(3, 3, 3, 4))
    }

    @Test("a tab-indented multibyte paragraph continuation line starts after its tab")
    func paragraphContinuationLeadingTab() throws {
        let nodes = nodes("foo\n\tbar\u{20AC}")
        let para = nodes.first { $0.kind == .paragraph }
        let texts = nodes.filter { $0.kind == .text }
        try #require(texts.count == 2 && texts[0].literal == "foo" && texts[1].literal == "bar\u{20AC}",
                     "fixture: two text runs `foo` / `bar€`")
        #expect(para?.range == r(1, 1, 2, 8))
        #expect(texts[0].range == r(1, 1, 1, 4))
        #expect(texts[1].range == r(2, 2, 2, 8))
    }
}

private struct EncNode {
    let kind: MarkdownNode.Kind
    let literal: String?
    let range: Range<MarkdownNode.SourcePosition>?
}

private func dfsEncNodes(_ node: borrowing MarkdownNode, into out: inout [EncNode]) {
    out.append(EncNode(kind: node.kind, literal: node.literal(), range: node.sourceRange))
    node.children.forEach { child in dfsEncNodes(child, into: &out) }
}
