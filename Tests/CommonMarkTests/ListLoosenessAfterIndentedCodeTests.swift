/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Blank lines following an indented code block are not part of it (Indented code blocks), so a blank line after a
/// list item's indented code block separates it from the item's next block or from the next item, and the list is
/// loose (Lists). A blank line followed by more code lines is inside the block and separates nothing.
@Suite("List looseness after an indented code block")
struct ListLoosenessAfterIndentedCodeTests {

    @Test("a blank line inside an item's indented code block keeps the list tight")
    func blankInsideIndentedCode() {
        #expect(TreeDump.dump("-     code\n\n      more\n- b\n", options: []) == """
            document
              list bullet '-' tight
                item
                  code_block "" "code\\n\\nmore\\n"
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("a blank line between an item's indented code block and its paragraph makes the list loose")
    func blankBetweenCodeAndParagraph() {
        #expect(TreeDump.dump("-     code\n\n  para\n", options: []) == """
            document
              list bullet '-' loose
                item
                  code_block "" "code\\n"
                  paragraph
                    text "para"

            """)
    }

    @Test("a blank line between an item ending in indented code and the next item makes the list loose")
    func blankBetweenItems() {
        #expect(TreeDump.dump("-     code\n\n- b\n", options: []) == """
            document
              list bullet '-' loose
                item
                  code_block "" "code\\n"
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("an ordered list is loose in the same shape")
    func orderedList() {
        #expect(TreeDump.dump("1.     code\n\n   para\n", options: []) == """
            document
              list ordered start=1 delim=period loose
                item
                  code_block "" "code\\n"
                  paragraph
                    text "para"

            """)
    }

    @Test("a list in a block quote is loose in the same shape")
    func inBlockQuote() {
        #expect(TreeDump.dump("> -     code\n>\n>   para\n", options: []) == """
            document
              block_quote
                list bullet '-' loose
                  item
                    code_block "" "code\\n"
                    paragraph
                      text "para"

            """)
    }
}
