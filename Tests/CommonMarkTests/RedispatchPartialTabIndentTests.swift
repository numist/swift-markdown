/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A container's continuation consumes part of a tab, a deeper container fails to continue, and the
/// line starts a new block in the surviving container. The tab's unconsumed columns count toward that
/// block's indentation (Tabs), deciding between an indented code block and a paragraph.
@Suite("New block indentation after a partially consumed container tab")
struct RedispatchPartialTabIndentTests {

    // The outer `>` takes one column of the tab; its two other columns plus two spaces are the code
    // indent.
    @Test("block-quote straddle: leftover tab columns reach the code indent")
    func blockQuoteStraddleTwoSpaces() {
        MarkdownDocument.withParsedDocument(">>```\n>\t  x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", "x\n"])
        }
    }

    @Test("block-quote straddle: one leftover space survives into the code content")
    func blockQuoteStraddleThreeSpaces() {
        MarkdownDocument.withParsedDocument(">>```\n>\t   x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", " x\n"])
        }
    }

    // The code indent takes the first tab's two leftover columns and two of the second tab's four;
    // the second tab's other two columns are content spaces.
    @Test("block-quote straddle: a tab split by the code indent leaves spaces in code content")
    func blockQuoteStraddleSplitTab() {
        MarkdownDocument.withParsedDocument(">>```\n>\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  x\n"])
        }
    }

    // The list item takes two of the tab's four columns; the other two fall short of the code indent.
    @Test("list-item straddle: leftover tab columns fall short of the code indent (bare tab)")
    func listItemStraddleBareTab() {
        MarkdownDocument.withParsedDocument("- >```\n\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    @Test("list-item straddle: one leading space then tab stays a paragraph")
    func listItemStraddleSpaceTab() {
        MarkdownDocument.withParsedDocument("- >```\n \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // The two spaces are the item's content indent; the tab then spans two columns.
    @Test("list-item straddle: two leading spaces then tab stays a paragraph")
    func listItemStraddleTwoSpacesTab() {
        MarkdownDocument.withParsedDocument("- >```\n  \tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    @Test("block-quote straddle boundary: bare tab stays a paragraph")
    func blockQuoteStraddleBoundaryBareTab() {
        MarkdownDocument.withParsedDocument(">>```\n>\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    @Test("block-quote straddle boundary: tab then one space stays a paragraph")
    func blockQuoteStraddleBoundaryTabSpace() {
        MarkdownDocument.withParsedDocument(">>```\n>\t x") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .blockQuote, .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    @Test("list-item boundary: unindented tail closes the list into a paragraph")
    func listItemBoundaryUnindented() {
        MarkdownDocument.withParsedDocument("- >```\nx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .blockQuote, .fencedCode(), .paragraph, .text])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }
}
