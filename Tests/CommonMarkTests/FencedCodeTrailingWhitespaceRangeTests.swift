/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Spaces and tabs after a closing code fence are ignored (Fenced code blocks), as is whitespace after an opening
/// fence's info string, so a fenced code block ends just past its closing fence's last fence character, or, when its
/// opening line is its last, just past its info string or opening fence. A content line loses the opening fence's
/// indentation, so a last line holding only that indentation, or only a container's prefix, has no content bytes, and
/// the block ends at the start of that line.
@Suite("Fenced code block ranges before trailing whitespace")
struct FencedCodeTrailingWhitespaceRangeTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: .sourcePosition, sourceRanges: true)
    }

    @Test("a closing fence followed by spaces and tabs", arguments: ["```\na\n```  \n", "```\na\n```\t\n"])
    func closingFence(_ source: String) {
        #expect(tree(source) == """
            document @1:1-4:1
              code_block "" "a\\n" @1:1-3:4

            """)
    }

    @Test
    func indentedFencesWithInfoString() {
        #expect(tree("  ```rust  \n  a\n  ```\t\n") == """
            document @1:1-4:1
              code_block "rust" "a\\n" @1:3-3:6

            """)
    }

    @Test
    func emptyBlockClosingFence() {
        #expect(tree("```\n```  \n") == """
            document @1:1-3:1
              code_block "" "" @1:1-2:4

            """)
    }

    @Test
    func unclosedOpeningFenceOnly() {
        #expect(tree("```  \n") == """
            document @1:1-2:1
              code_block "" "" @1:1-1:4

            """)
    }

    @Test
    func unclosedOpeningFenceWithInfoStringOnly() {
        #expect(tree("``` rust  \n") == """
            document @1:1-2:1
              code_block "rust" "" @1:1-1:9

            """)
    }

    @Test
    func openingFenceOnlyClosedByContainer() {
        #expect(tree("> ```  \nb\n") == """
            document @1:1-3:1
              block_quote @1:1-1:6
                code_block "" "" @1:3-1:6
              paragraph @2:1-2:2
                text "b" @2:1-2:2

            """)
    }

    @Test
    func listItemEndsAtClosingFence() {
        #expect(tree("- ```\n  a\n  ```  \n") == """
            document @1:1-4:1
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  code_block "" "a\\n" @1:3-3:6

            """)
    }

    @Test
    func lastLineOfStrippedIndentation() {
        #expect(tree("  ```\n  a\n  \n") == """
            document @1:1-4:1
              code_block "" "a\\n\\n" @1:3-3:1

            """)
    }

    @Test
    func lastLineOfContainerPrefixOnly() {
        #expect(tree("> ```\n> \n") == """
            document @1:1-3:1
              block_quote @1:1-2:2
                code_block "" "\\n" @1:3-2:1

            """)
    }

    @Test
    func lastLineOfPartlyStrippedTab() {
        #expect(tree(">\t```\n>\t") == """
            document @1:1-2:3
              block_quote @1:1-2:2
                code_block "" "\\n" @1:3-2:1

            """)
    }

    @Test
    func lastLineWhitespaceBeyondIndentation() {
        #expect(tree("```\n  \n") == """
            document @1:1-3:1
              code_block "" "  \\n" @1:1-2:3

            """)
    }

    @Test
    func lastContentLineKeepsItsWhitespace() {
        #expect(tree("```\na  \n") == """
            document @1:1-3:1
              code_block "" "a  \\n" @1:1-2:4

            """)
    }
}
