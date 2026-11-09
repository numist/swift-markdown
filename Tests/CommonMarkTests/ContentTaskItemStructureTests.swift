/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Recognition of a task list item with content after its checkbox, at the top level and nested.
///
/// A task list item is a list item whose first block is a paragraph beginning with a task list item
/// marker (spec "Task list items (extension)"). That depends only on the item's own first paragraph, so
/// an item is recognized however deeply it is nested and whatever container markers precede it on its
/// line.
@Suite("Task list items with content")
struct ContentTaskItemStructureTests {

    // MARK: - Top-level items

    @Test("a top-level task list item is recognized and its checkbox is not text")
    func topLevelContentTaskRecognized() {
        #expect(TreeDump.dump("- [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "x"

            """)
    }

    @Test("indented top-level content task item is recognized")
    func indentedTopLevelContentTaskRecognized() {
        // Three spaces is the most indentation a list item may have without becoming indented code (List items).
        #expect(TreeDump.dump("   - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "x"

            """)
    }

    @Test("top-level checked content task item is recognized")
    func topLevelCheckedContentTaskRecognized() {
        #expect(TreeDump.dump("- [x] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "x"

            """)
    }

    @Test("a top-level task list item whose checkbox is followed by a tab is recognized")
    func topLevelTabSeparatorContentTaskRecognized() {
        #expect(TreeDump.dump("- [ ]\tx", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "x"

            """)
    }

    // MARK: - Nested / block-quoted items

    @Test("task list item in a block quote is recognized")
    func blockQuotedContentTaskRecognized() {
        #expect(TreeDump.dump("> - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              block_quote
                list bullet '-' tight
                  tasklist unchecked
                    paragraph
                      text "x"

            """)
    }

    @Test("task list item sharing its line with an outer list marker is recognized")
    func nestedContentTaskRecognized() {
        #expect(TreeDump.dump("- - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    tasklist unchecked
                      paragraph
                        text "x"

            """)
    }

    @Test("task list item nested three deep is recognized")
    func threeDeepNestedContentTaskRecognized() {
        #expect(TreeDump.dump("- - - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    item
                      list bullet '-' tight
                        tasklist unchecked
                          paragraph
                            text "x"

            """)
    }

    @Test("task list item in a block quote in a list item is recognized")
    func taskInBlockQuoteInListRecognized() {
        #expect(TreeDump.dump("- > - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    list bullet '-' tight
                      tasklist unchecked
                        paragraph
                          text "x"

            """)
    }

    @Test("task list item nested in an ordered list item is recognized")
    func orderedNestedContentTaskRecognized() {
        #expect(TreeDump.dump("1. - [ ] x", options: [.tasklist, .sourcePosition]) == """
            document
              list ordered start=1 delim=period tight
                item
                  list bullet '-' tight
                    tasklist unchecked
                      paragraph
                        text "x"

            """)
    }

    // MARK: - Nested on its own line

    @Test("task list item in a sublist on its own line is recognized")
    func sublistItemOnOwnLineIsRecognized() {
        #expect(TreeDump.dump("- a\n  - [ ] b", options: [.tasklist, .sourcePosition]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                  list bullet '-' tight
                    tasklist unchecked
                      paragraph
                        text "b"

            """)
    }
}
