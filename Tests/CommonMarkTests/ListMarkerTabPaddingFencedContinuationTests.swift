/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A fenced-code body line that is itself a NEW list marker followed by a tab. The marker's optional
/// padding column must be measured in COLUMNS, not bytes (cmark's `parse_list_marker`): a tab run of
/// five-or-more columns consumes only one optional column and leaves the rest as content, and when the
/// content reaches four columns of indent it is an indented code block, not a nested list. The rewrite
/// previously counted each padding tab as a single byte and re-dispatched the trailing marker as a
/// nested list.
@Suite("List-marker padding tab feeding an indented code body")
struct ListMarkerTabPaddingFencedContinuationTests {

    // FIX: `-\t\t-` opens a sibling item; the marker takes `-` plus one optional column of the first
    // tab (column 1 → 2). The remaining six columns reach the four-column code indent, so the tail (`-`)
    // is an INDENTED code block whose split second tab leaves two leading content spaces. The rewrite
    // previously consumed both tabs as padding and re-dispatched the trailing `-` as a nested list.
    @Test("double-tab list continuation opens a sibling item with indented code")
    func doubleTabSiblingIndentedCode() throws {
        try MarkdownDocument.withParsedDocument("- ```\n-\t\t-") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [
                .document, .bulletList(), .item(checked: nil), .fencedCode(),
                .item(checked: nil), .indentedCode,
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  -\n"])
        }
    }

    // FIX: same shape with `x` as the content byte — the two split-tab columns precede it.
    @Test("double-tab list continuation with content keeps the split-tab spaces")
    func doubleTabSiblingIndentedCodeContent() throws {
        try MarkdownDocument.withParsedDocument("- ```\n-\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [
                .document, .bulletList(), .item(checked: nil), .fencedCode(),
                .item(checked: nil), .indentedCode,
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  x\n"])
        }
    }

    // FIX: a tilde fence and a tab-then-two-spaces continuation. The marker takes `*` plus one optional
    // column of the tab (column 1 → 2); the tab's remaining columns plus the two spaces reach exactly
    // four columns of code indent, so the tail (`-`) is an indented code block with no leading space.
    @Test("tab-then-spaces list continuation opens a sibling item with indented code")
    func tabThenSpacesSiblingIndentedCode() throws {
        try MarkdownDocument.withParsedDocument("*\t~~~\n*\t  -") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [
                .document, .bulletList(.asterisk), .item(checked: nil), .fencedCode(.tilde),
                .item(checked: nil), .indentedCode,
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "-\n"])
        }
    }

    // GUARD: a SINGLE tab after the marker is three columns — below the five-column reset — so the whole
    // tab is padding and the content column is four. The tail (`x`) sits AT the item's content column,
    // so it is an ordinary paragraph, not an indented code block and not a nested list.
    @Test("single-tab list continuation opens a sibling item with a paragraph")
    func singleTabSiblingParagraph() throws {
        try MarkdownDocument.withParsedDocument("- ```\n-\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [
                .document, .bulletList(), .item(checked: nil), .fencedCode(),
                .item(checked: nil), .paragraph, .text,
            ])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // FIX: the same straddle for an ORDERED marker (`1.`, two bytes wide). The marker takes `1.` plus one
    // optional column of the first tab (column 2 → 3); the run reaches six columns (≥ 5 reset), so the
    // tail (`x`) is an indented code block whose split second tab leaves one leading content space.
    @Test("double-tab ordered-list continuation opens a sibling item with indented code")
    func orderedMarkerDoubleTabSiblingIndentedCode() throws {
        try MarkdownDocument.withParsedDocument("1. ```\n1.\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [
                .document, .orderedList(), .item(checked: nil), .fencedCode(),
                .item(checked: nil), .indentedCode,
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", " x\n"])
        }
    }
}
