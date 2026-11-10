/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A container's continuation consumes part of a tab, a deeper container fails to continue, and the
/// line starts a new block in the surviving container. The tab's unconsumed columns count toward that
/// block's indentation (Tabs), deciding between an indented code block and a paragraph.
@Suite("New block indentation after a partially consumed container tab")
struct NewBlockIndentAfterPartialTabTests {

    // The outer `>` takes one column of the tab; its two other columns plus two spaces are the code
    // indent.
    @Test("block-quote straddle: leftover tab columns reach the code indent")
    func blockQuoteStraddleTwoSpaces() {
        #expect(TreeDump.dump(">>```\n>\t  x", options: []) == """
            document
              block_quote
                block_quote
                  code_block "" ""
                code_block "" "x\\n"

            """)
        #expect(codeBlockKinds(">>```\n>\t  x") == ["code_block fenced fence='`' length=3 offset=0", "code_block indented fence=none length=0 offset=0"])
    }

    @Test("block-quote straddle: one leftover space survives into the code content")
    func blockQuoteStraddleThreeSpaces() {
        #expect(TreeDump.dump(">>```\n>\t   x", options: []) == """
            document
              block_quote
                block_quote
                  code_block "" ""
                code_block "" " x\\n"

            """)
        #expect(codeBlockKinds(">>```\n>\t   x") == ["code_block fenced fence='`' length=3 offset=0", "code_block indented fence=none length=0 offset=0"])
    }

    // The code indent takes the first tab's two leftover columns and two of the second tab's four;
    // the second tab's other two columns are content spaces.
    @Test("block-quote straddle: a tab split by the code indent leaves spaces in code content")
    func blockQuoteStraddleSplitTab() {
        #expect(TreeDump.dump(">>```\n>\t\tx", options: []) == """
            document
              block_quote
                block_quote
                  code_block "" ""
                code_block "" "  x\\n"

            """)
        #expect(codeBlockKinds(">>```\n>\t\tx") == ["code_block fenced fence='`' length=3 offset=0", "code_block indented fence=none length=0 offset=0"])
    }

    // The list item takes two of the tab's four columns; the other two fall short of the code indent.
    @Test("list-item straddle: leftover tab columns fall short of the code indent (bare tab)")
    func listItemStraddleBareTab() {
        #expect(TreeDump.dump("- >```\n\tx", options: []) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    code_block "" ""
                  paragraph
                    text "x"

            """)
        #expect(codeBlockKinds("- >```\n\tx") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("list-item straddle: one leading space then tab stays a paragraph")
    func listItemStraddleSpaceTab() {
        #expect(TreeDump.dump("- >```\n \tx", options: []) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    code_block "" ""
                  paragraph
                    text "x"

            """)
        #expect(codeBlockKinds("- >```\n \tx") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    // The two spaces are the item's content indent; the tab then spans two columns.
    @Test("list-item straddle: two leading spaces then tab stays a paragraph")
    func listItemStraddleTwoSpacesTab() {
        #expect(TreeDump.dump("- >```\n  \tx", options: []) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    code_block "" ""
                  paragraph
                    text "x"

            """)
        #expect(codeBlockKinds("- >```\n  \tx") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("block-quote straddle boundary: tab then one space stays a paragraph")
    func blockQuoteStraddleBoundaryTabSpace() {
        #expect(TreeDump.dump(">>```\n>\t x", options: []) == """
            document
              block_quote
                block_quote
                  code_block "" ""
                paragraph
                  text "x"

            """)
        #expect(codeBlockKinds(">>```\n>\t x") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("list-item boundary: unindented tail closes the list into a paragraph")
    func listItemBoundaryUnindented() {
        #expect(TreeDump.dump("- >```\nx", options: []) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    code_block "" ""
              paragraph
                text "x"

            """)
        #expect(codeBlockKinds("- >```\nx") == ["code_block fenced fence='`' length=3 offset=0"])
    }
}
