/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// When a container-continuation prefix partially consumes a straddling tab and a deeper container
/// then fails to match, the closed leaf's line is re-dispatched as a fresh block at the surviving
/// container's level. The re-dispatch indent must be measured from the surviving prefix's COLUMN,
/// counting the tab's already-consumed columns (cmark's `partially_consumed_tab`; blocks.c
/// `S_advance_offset` + `add_line`), not by recounting the whole tab from column 0. Recounting from
/// column 0 either drops the leftover columns (block-quote straddle → under-count) or double-counts
/// the consumed columns (list-item content-indent straddle → over-count), flipping the
/// indented-code / paragraph decision.
@Suite("Re-dispatch indent after a partially-consumed prefix tab")
struct RedispatchPartialTabIndentTests {

    // FIX: after the outer `>` consumes one column of the tab (column 1 → 2), the tab's two leftover
    // columns plus two spaces reach four columns of indent, so `x` re-dispatches as an INDENTED code
    // block, not a paragraph.
    @Test("block-quote straddle: leftover tab columns reach the code indent")
    func blockQuoteStraddleUnderCountTwoSpaces() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\t  x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", "x\n"])
        }
    }

    // FIX: five columns of indent (two leftover tab columns + three spaces); four are stripped as the
    // code indent, leaving one leading content space before `x`.
    @Test("block-quote straddle: one leftover space survives into the code content")
    func blockQuoteStraddleUnderCountThreeSpaces() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\t   x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", " x\n"])
        }
    }

    // FIX: a SECOND tab straddles the four-column code-indent boundary during re-dispatch. The outer
    // `>` consumes one column of the first tab (column 1 → 2); the first tab's two leftover columns
    // reach column 4, and two columns of the second tab (columns 4-6) complete the four-column code
    // indent. The second tab's remaining two columns (6-8) surface as leading content spaces with its
    // byte dropped (cmark's `partially_consumed_tab`), then `x` — code content `  x`.
    @Test("block-quote straddle: a re-dispatched straddling tab surfaces leftover spaces in code content")
    func blockQuoteStraddleRedispatchSplitTab() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  x\n"])
        }
    }

    // FIX: the list item consumes two columns of indent (into the tab), so the tab's two leftover
    // columns do NOT reach the four-column code indent; `x` re-dispatches as a PARAGRAPH, not an
    // indented code block.
    @Test("list-item straddle: leftover tab columns fall short of the code indent (bare tab)")
    func listItemStraddleOverCountBareTab() throws {
        try MarkdownDocument.withParsedDocument("- >```\n\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // FIX: one leading space then the tab; the item still consumes two columns and the leftover falls
    // short of the code indent.
    @Test("list-item straddle: one leading space then tab stays a paragraph")
    func listItemStraddleOverCountSpaceTab() throws {
        try MarkdownDocument.withParsedDocument("- >```\n \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // FIX: two leading spaces exactly satisfy the item content column, so the following tab is fully
    // leftover; its four columns from column 2 still fall short (only two reach), staying a paragraph.
    @Test("list-item straddle: two leading spaces then tab stays a paragraph")
    func listItemStraddleOverCountTwoSpacesTab() throws {
        try MarkdownDocument.withParsedDocument("- >```\n  \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // GUARD: the block-quote straddle boundary. `>\tx` leaves two columns of indent (< 4), a paragraph.
    // Must stay a paragraph.
    @Test("block-quote straddle boundary: bare tab stays a paragraph (unchanged)")
    func blockQuoteStraddleBoundaryBareTab() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // GUARD: `>\t x` leaves three columns of indent (< 4), a paragraph. Must stay a paragraph.
    @Test("block-quote straddle boundary: tab then one space stays a paragraph (unchanged)")
    func blockQuoteStraddleBoundaryTabSpace() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\t x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // GUARD: the list-item boundary with no leading whitespace at all. `x` is below the item content
    // column, so the list closes and `x` is a top-level paragraph. Must stay a paragraph.
    @Test("list-item boundary: unindented tail closes the list into a paragraph (unchanged)")
    func listItemBoundaryUnindented() throws {
        try MarkdownDocument.withParsedDocument("- >```\nx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }
}
