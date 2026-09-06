/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A tab that immediately follows a block-quote marker (`>`) and feeds a fenced code body must be
/// PARTIALLY consumed: the marker takes `>` plus one optional following COLUMN (cmark's
/// `parse_block_quote_prefix`), so a straddling tab has its remaining columns surfaced as leading
/// spaces in the code content (cmark's `partially_consumed_tab`; blocks.c `add_line`). The rewrite
/// previously advanced past the whole tab byte, dropping those leftover columns.
@Suite("Block-quote-prefix tab feeding a fenced code body")
struct BlockQuotePrefixTabFencedCodeTests {

    // FIX: `>` is column 1, so the tab at column 2 spans columns 2-4 (3 wide); the marker consumes one
    // optional column, leaving two columns that materialize as two content spaces.
    @Test("tab right after `>` leaves two content spaces")
    func tabAfterMarkerLeavesTwoSpaces() throws {
        try MarkdownDocument.withParsedDocument(">```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == ["  \n"])
        }
    }

    // FIX: the two leftover tab columns precede the literal `x`.
    @Test("tab right after `>` then content keeps the leftover spaces before the content")
    func tabAfterMarkerThenContent() throws {
        try MarkdownDocument.withParsedDocument(">```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == ["  x\n"])
        }
    }

    // FIX: the opening fence carries a trailing space (`> ` + backticks), but the body line is `>\t`
    // (no space), so the tab still straddles the marker's optional column and leaves two spaces.
    @Test("opening fence with a trailing space, body tab still leaves two spaces")
    func openingFenceSpaceBodyTab() throws {
        try MarkdownDocument.withParsedDocument("> ```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == ["  \n"])
        }
    }

    // FIX: doubly nested. After `>>` the column is 2, so the tab at column 2 spans columns 2-3 (2
    // wide); one optional column is consumed, leaving a single content space.
    @Test("tab after a doubly-nested `>>` leaves one content space")
    func tabAfterNestedMarkers() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == [" \n"])
        }
    }

    // GUARD: a space between `>` and the tab is itself the marker's optional column, so the tab is
    // then literal code content - not split. Must stay untouched.
    @Test("space then tab keeps the tab as literal code content")
    func spaceThenTabIsLiteral() throws {
        try MarkdownDocument.withParsedDocument("> ```\n> \t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == ["\t\n"])
        }
    }

    // GUARD: the sibling fence-indent strip site (no block quote). A one-space-indented fence strips
    // one column; the body tab at column 0 spans columns 0-3 (4 wide), losing one column to the strip
    // and leaving three content spaces.
    @Test("indented-fence body tab splits at the fence-indent boundary (unchanged)")
    func indentedFenceBodyTab() throws {
        try MarkdownDocument.withParsedDocument(" ```\n\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .fencedCode(offset: 1)])
            #expect(codeBlocks(doc).map(\.literal) == ["   x\n"])
        }
    }

    // GUARD: the sibling list-item content-indent strip site. The two spaces satisfy the item's
    // content column exactly, so the following tab is literal code content - not split. Must stay
    // untouched.
    @Test("list-item fenced body tab stays literal after the content indent (unchanged)")
    func listItemFenceBodyTab() throws {
        try MarkdownDocument.withParsedDocument("- ```\n  \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == ["\tx\n"])
        }
    }

    // GUARD: a non-fenced-code context. `>\tx` on one line pre-expands its prefix tab to spaces, so
    // the leftover columns are stripped as paragraph leading whitespace (content is just `x`).
    @Test("tab after `>` in a paragraph strips to first content (unchanged)")
    func tabAfterMarkerParagraph() throws {
        try MarkdownDocument.withParsedDocument(">\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .paragraph, .text])
            #expect(dfs(doc).compactMap(\.literal) == ["x"])
        }
    }

    // GUARD: a non-fenced-code context. `>\t# h` is an ATX heading whose leading whitespace is
    // stripped; content is `h`.
    @Test("tab after `>` before an ATX heading strips to the heading text (unchanged)")
    func tabAfterMarkerHeading() throws {
        try MarkdownDocument.withParsedDocument(">\t# h") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .heading(level: 1), .text])
            #expect(dfs(doc).compactMap(\.literal) == ["h"])
        }
    }

    // FIX: the tab straddle only splits when the code body actually continues. Here the inner `>` is
    // absent on the body line, so the deeper block quote fails to match and the code block closes; the
    // tail (`x`) is re-dispatched as a fresh block. The partially-consumed tab must NOT then count as
    // indented-code indentation: cmark keeps only the tab's leftover columns (< 4) as indent, so `x`
    // becomes a Paragraph under the outer quote, never an indented code block.
    @Test("dropped inner `>` re-dispatches the tail as a paragraph, not indented code")
    func nestedInnerMarkerAbsentReDispatchesParagraph() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // GUARD: the same dropped-inner-`>` shape with a blank tail keeps only the empty nested code block
    // (the failed inner marker closes nothing else, and the blank line adds no content).
    @Test("dropped inner `>` with a blank tail keeps just the empty nested code block")
    func nestedInnerMarkerAbsentBlankTail() throws {
        try MarkdownDocument.withParsedDocument(">>```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode()])
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }
}
