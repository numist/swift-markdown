/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A fenced code block keeps every line inside its fences, blank ones included, and one left unclosed runs to the end
/// of its container (Fenced code blocks). An HTML block whose end condition never matches also runs to the end of its
/// container (HTML blocks), so a final blank line belongs to its content.
@Suite("Final blank line of a fenced code or HTML block")
struct UnclosedBlockFinalBlankLineTests {

    @Test("a fenced body of one blank line is that line's newline")
    func closedFenceBlankBody() {
        #expect(TreeDump.dump("```\n\n```\n", options: []) == """
            document
              code_block "" "\\n"

            """)
    }

    @Test("an unclosed fence followed by a blank line has that blank line as its body")
    func unclosedFenceBlankLine() {
        #expect(TreeDump.dump("```\n\n", options: []) == """
            document
              code_block "" "\\n"

            """)
    }

    @Test("a whitespace-only line within an indented fence's offset is a blank body line")
    func unclosedIndentedFenceWhitespaceLine() {
        #expect(TreeDump.dump(" ```\n \n", options: []) == """
            document
              code_block "" "\\n"

            """)
    }

    @Test("an unclosed fence in a block quote keeps a blank quoted line")
    func unclosedFenceInBlockQuote() {
        #expect(TreeDump.dump("> ```\n>\n", options: []) == """
            document
              block_quote
                code_block "" "\\n"

            """)
    }

    @Test("an unclosed fence ending a list item keeps the blank line before the next item")
    func unclosedFenceInListItem() {
        #expect(TreeDump.dump("- ```\n\n- b\n", options: []) == """
            document
              list bullet '-' tight
                item
                  code_block "" "\\n"
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("an HTML block whose end condition never matches keeps a final blank line")
    func unterminatedHTMLBlockBlankLine() {
        #expect(TreeDump.dump("<!X\n\n", options: []) == """
            document
              html_block "<!X\\n\\n"

            """)
    }
}
