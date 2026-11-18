/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// The tab after the list marker is one byte but three columns (Tabs), so the fence's byte offset differs from its
// column.
@Suite("Info string of a fence opening a tab-indented list item")
struct FencedInfoStringInTabIndentedListItemTests {

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
