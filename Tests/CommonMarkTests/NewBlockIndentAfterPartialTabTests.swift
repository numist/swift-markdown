/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("New block indentation where a nested container fails to continue")
struct NewBlockIndentAfterPartialTabTests {

    @Test("block quote: the tab's leftover columns and two spaces reach the code indent")
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

    @Test("block quote: with three spaces, one space is code content")
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

    @Test("block quote: the code indent splits a second tab, leaving two spaces of code content")
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

    @Test("list item: a tab's leftover columns fall short of the code indent")
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

    @Test("list item: a space then a tab stays a paragraph")
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
    @Test("list item: two spaces then a tab stays a paragraph")
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

    @Test("block quote: a tab then one space stays a paragraph")
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

    @Test("list item: an unindented line closes the list and starts a paragraph")
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
