/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A block quote marker is `>` plus an optional following space (Block quotes). When a tab follows the `>`, the
/// marker takes one of the tab's columns and the rest are indentation (Tabs), so on a fenced code block's
/// content line they become leading spaces of the content.
@Suite("Tab after a block quote marker in a fenced code block")
struct BlockQuotePrefixTabFencedCodeTests {

    // The tab spans columns 2-4.
    @Test("tab right after `>` leaves two content spaces")
    func tabAfterMarkerLeavesTwoSpaces() {
        MarkdownDocument.withParsedDocument(">```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == ["  \n"])
        }
    }

    @Test("tab right after `>` then content keeps the leftover spaces before the content")
    func tabAfterMarkerThenContent() {
        MarkdownDocument.withParsedDocument(">```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == ["  x\n"])
        }
    }

    @Test("a space after `>` on the opening fence line, a tab on the content line, leaves two spaces")
    func openingFenceSpaceBodyTab() {
        MarkdownDocument.withParsedDocument("> ```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == ["  \n"])
        }
    }

    // The tab spans columns 3-4.
    @Test("tab after a nested `>>` leaves one content space")
    func tabAfterNestedMarkers() {
        MarkdownDocument.withParsedDocument(">>```\n>>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == [" \n"])
        }
    }

    @Test("space then tab keeps the tab as literal code content")
    func spaceThenTabIsLiteral() {
        MarkdownDocument.withParsedDocument("> ```\n> \t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == ["\t\n"])
        }
    }

    // Per Fenced code blocks, a fence indented one space removes one space of indentation from each content
    // line; the remaining three columns of the tab stay.
    @Test("a content line tab under a one-space-indented fence leaves three spaces")
    func indentedFenceBodyTab() {
        MarkdownDocument.withParsedDocument(" ```\n\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "code_block fenced fence='`' length=3 offset=1"])
            #expect(codeBlocks(doc).map(\.literal) == ["   x\n"])
        }
    }

    @Test("a tab after a list item's content indentation stays literal in a fenced code block")
    func listItemFenceBodyTab() {
        MarkdownDocument.withParsedDocument("- ```\n  \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "list bullet '-' tight", "item", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == ["\tx\n"])
        }
    }

    @Test("tab after `>` before a paragraph is stripped as leading whitespace")
    func tabAfterMarkerParagraph() {
        MarkdownDocument.withParsedDocument(">\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .paragraph, .text])
            #expect(dfs(doc).compactMap(\.literal) == ["x"])
        }
    }

    @Test("tab after `>` before an ATX heading is stripped as leading whitespace")
    func tabAfterMarkerHeading() {
        MarkdownDocument.withParsedDocument(">\t# h") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .heading(level: 1), .text])
            #expect(dfs(doc).compactMap(\.literal) == ["h"])
        }
    }

    // Without the inner `>`, the inner block quote and its code block close. The two leftover columns of the
    // tab are fewer than the four an indented code block needs, so `x` starts a paragraph in the outer block
    // quote.
    @Test("a missing inner `>` leaves the rest of the line a paragraph, not indented code")
    func nestedInnerMarkerAbsentReDispatchesParagraph() {
        MarkdownDocument.withParsedDocument(">>```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "block_quote", "code_block fenced fence='`' length=3 offset=0", "paragraph", "text"])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    @Test("a missing inner `>` before a blank rest of line leaves just the empty code block")
    func nestedInnerMarkerAbsentBlankTail() {
        MarkdownDocument.withParsedDocument(">>```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

    // The opening fence's indentation counts the partially consumed tab as one space, so a content line loses
    // one column of its tab to the marker and one to the fence indentation, leaving one content space.
    @Test("tab after `>` on the opening fence line leaves one content space")
    func openingLineTabFenceOffsetLeavesOneSpace() {
        MarkdownDocument.withParsedDocument(">\t```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=1"])
            #expect(codeBlocks(doc).map(\.literal) == [" \n"])
        }
    }

    @Test("tab after `>` on the opening fence line keeps one space before content")
    func openingLineTabFenceOffsetThenContent() {
        MarkdownDocument.withParsedDocument(">\t```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=1"])
            #expect(codeBlocks(doc).map(\.literal) == [" x\n"])
        }
    }
}
