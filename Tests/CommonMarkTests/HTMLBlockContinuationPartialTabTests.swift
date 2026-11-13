/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Tabs at the start of HTML block continuation content, inside, after or without a container prefix.
///
/// Per Tabs, a tab that a block quote marker's optional space or a list item's content indentation consumes only part
/// of leaves its remaining columns as spaces in the line's content, while a tab that no prefix touches stays literal.
@Suite("Tabs at the start of HTML block continuation content")
struct HTMLBlockContinuationPartialTabTests {

    static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test
    func blockQuoteMarkerSpaceInTab() {
        #expect(TreeDump.dump("> <div>\n>\tfoo\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              block_quote @1:1-2:6
                html_block "<div>\\n  foo\\n" @1:3-2:6

            """)
    }

    @Test
    func listItemIndentInTab() {
        #expect(TreeDump.dump("- <div>\n \tfoo\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  html_block "<div>\\n  foo\\n" @1:3-2:6

            """)
    }

    @Test
    func blockQuoteMarkerSpaceBeforeTab() {
        #expect(TreeDump.dump("> <div>\n> \tfoo\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              block_quote @1:1-2:7
                html_block "<div>\\n\\tfoo\\n" @1:3-2:7

            """)
    }

    @Test
    func topLevelTab() {
        #expect(TreeDump.dump("<div>\n\tfoo\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              html_block "<div>\\n\\tfoo\\n" @1:1-2:5

            """)
    }

    @Test
    func typeOneBlockQuoteMarkerSpaceInTab() {
        #expect(TreeDump.dump("> <pre>\n>\tfoo\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              block_quote @1:1-2:6
                html_block "<pre>\\n  foo\\n" @1:3-2:6

            """)
    }
}
