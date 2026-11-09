/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task list item's first block must be a paragraph (Task list items (extension)), so an item whose
/// first block is a setext heading has no checkbox and the heading keeps `[ ]` as text.
@Suite("Task list item marker in a setext heading")
struct TaskListSetextHeadingRecognitionTests {

    @Test("`- [ ] v\\n  -` is an item without a checkbox, holding a level-2 heading `[ ] v`")
    func taskItemSetextHeadingNotRecognized() {
        #expect(TreeDump.dump("- [ ] v\n  -", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  heading 2
                    text "[ ] v"

            """)
    }

    // MARK: - Without a checkbox or an underline

    @Test("`- [ ] v` (no underline) is an unchecked task list item with a paragraph `v`")
    func openingLineOnlyIsTaskListItem() {
        #expect(TreeDump.dump("- [ ] v", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "v"

            """)
    }

    @Test("`- v\\n  -` is an item without a checkbox, holding a level-2 heading `v`")
    func plainItemSetextHeading() {
        #expect(TreeDump.dump("- v\n  -", options: [.tasklist]) == """
            document
              list bullet '-' tight
                item
                  heading 2
                    text "v"

            """)
    }
}
