/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// When a tab follows `>`, the block quote marker's optional space takes one of the tab's columns and the rest are
// indentation (Tabs), which a fenced code block's content line keeps as leading spaces.
@Suite("Tabs after a block quote marker and in fenced code block indentation")
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

    // The fence's one space of indentation is removed from each content line (Fenced code blocks), which takes one of
    // the tab's columns (Tabs).
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

    // The tab's two leftover columns are fewer than the four an indented code block needs.
    @Test("a missing inner `>` leaves the rest of the line a paragraph, not indented code")
    func nestedInnerMarkerAbsentOpensParagraph() {
        MarkdownDocument.withParsedDocument(">>```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "block_quote", "code_block fenced fence='`' length=3 offset=0", "paragraph", "text"])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
        #expect(TreeDump.dump(">>```\n>\tx", options: []) == "document\n  block_quote\n    block_quote\n      code_block \"\" \"\"\n    paragraph\n      text \"x\"\n")
    }

    @Test("a missing inner `>` before a blank rest of line leaves just the empty code block")
    func nestedInnerMarkerAbsentBlankTail() {
        MarkdownDocument.withParsedDocument(">>```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "block_quote", "code_block fenced fence='`' length=3 offset=0"])
            #expect(codeBlocks(doc).map(\.literal) == [""])
        }
    }

    // The opening fence is indented by the two columns of its tab that the marker leaves, so each content line loses
    // the two columns its own tab has left.
    @Test("tab after `>` on the opening fence line leaves no content spaces")
    func openingLineTabFenceOffsetLeavesNoSpace() {
        MarkdownDocument.withParsedDocument(">\t```\n>\t") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=2"])
            #expect(codeBlocks(doc).map(\.literal) == ["\n"])
        }
    }

    @Test("tab after `>` on the opening fence line leaves the content unindented")
    func openingLineTabFenceOffsetThenContent() {
        MarkdownDocument.withParsedDocument(">\t```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == ["document", "block_quote", "code_block fenced fence='`' length=3 offset=2"])
            #expect(codeBlocks(doc).map(\.literal) == ["x\n"])
        }
    }
}
