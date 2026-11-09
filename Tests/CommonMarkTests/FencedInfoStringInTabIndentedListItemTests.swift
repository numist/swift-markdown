/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A fenced code block that opens a list item whose marker is followed by a tab. The tab advances to the next tab stop
/// (Tabs), so the item's content starts at the fence, one byte but three columns past the end of the marker (List
/// items), and the info string follows the fence.
@Suite("Info string of a fence opening a tab-indented list item")
struct FencedInfoStringInTabIndentedListItemTests {

    /// The unindented ``` line opens a second, top-level fence with an empty info string.
    @Test func infoString() {
        #expect(TreeDump.dump("*\t```n\na\n```", options: []) == """
            document
              list bullet '*' tight
                item
                  code_block "n" ""
              paragraph
                text "a"
              code_block "" ""

            """)
    }

    @Test func infoStringRunsToEndOfInput() {
        #expect(TreeDump.dump("*\t```n", options: []) == """
            document
              list bullet '*' tight
                item
                  code_block "n" ""

            """)
    }

    /// `\+` in the info string is `+` (Backslash escapes).
    @Test func escapedInfoString() {
        #expect(TreeDump.dump("*\t```foo\\+bar\nx\n```", options: []) == """
            document
              list bullet '*' tight
                item
                  code_block "foo+bar" ""
              paragraph
                text "x"
              code_block "" ""

            """)
    }
}
