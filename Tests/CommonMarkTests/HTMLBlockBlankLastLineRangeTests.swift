/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An HTML block of types 1 to 5 holds the blank lines before its end condition (HTML blocks). A blank last line that
/// holds only a container's prefix has no content bytes, so the block ends at the start of that line, while whitespace
/// left after the prefix is content.
@Suite("HTML block ranges ending in a blank line")
struct HTMLBlockBlankLastLineRangeTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: .sourcePosition, sourceRanges: true)
    }

    @Test("a last line of only a block quote marker", arguments: ["> <pre>\n>\n", "> <pre>\n> \n"])
    func blockQuotePrefixOnly(_ source: String) {
        #expect(tree(source) == """
            document @1:1-3:1
              block_quote @1:1-2:2
                html_block "<pre>\\n\\n" @1:3-2:1

            """)
    }

    @Test
    func emptyLastLine() {
        #expect(tree("<pre>\n\n") == """
            document @1:1-3:1
              html_block "<pre>\\n\\n" @1:1-2:1

            """)
    }

    @Test
    func whitespaceAfterPrefixIsContent() {
        #expect(tree(">\t<pre>\n>\t\n") == """
            document @1:1-3:1
              block_quote @1:1-2:3
                html_block "  <pre>\\n  \\n" @1:2-2:3

            """)
    }
}
