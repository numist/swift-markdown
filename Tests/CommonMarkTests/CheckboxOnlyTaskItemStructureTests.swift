/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Block structure of a task list item whose first line holds only the checkbox and trailing
/// whitespace (`- [ ] ` / `- [x]\t`).
///
/// The line is not blank, so it opens the item's paragraph (List items), which a following line
/// continues as paragraph continuation text, indented or as a lazy continuation line. The paragraph
/// begins with a task list item marker followed by whitespace, so the item is a task list item (Task
/// list items (extension)); the marker becomes the checkbox, and a paragraph left with no content is
/// removed.
@Suite("Checkbox-only task list item block structure")
struct CheckboxOnlyTaskItemStructureTests {

    @Test("a checkbox-only task list item line is continued by a lazy continuation line")
    func checkboxOnlyTaskItemLineContinuedLazily() {
        #expect(TreeDump.dump("- [ ] \nx", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                tasklist unchecked @1:1-2:2
                  paragraph @2:1-2:2
                    text "x" @2:1-2:2

            """)
    }

    @Test("a checkbox-only task list item followed by a blank line then text")
    func checkboxOnlyTaskItemBeforeBlankThenText() {
        #expect(TreeDump.dump("- [ ] \n\nx", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:2
              list bullet '-' tight @1:1-1:6
                tasklist unchecked @1:1-1:6
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """)
    }

    @Test("a checkbox-only task list item as the last line")
    func checkboxOnlyTaskItemAtEOF() {
        #expect(TreeDump.dump("- [ ] ", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-1:7
              list bullet '-' tight @1:1-1:6
                tasklist unchecked @1:1-1:6

            """)
    }

    @Test("a checkbox-only task list item followed by an indented line continues the item")
    func checkboxOnlyTaskItemContinuesOnIndentedLine() {
        #expect(TreeDump.dump("- [ ] \n  x", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:4
              list bullet '-' tight @1:1-2:4
                tasklist unchecked @1:1-2:4
                  paragraph @2:3-2:4
                    text "x" @2:3-2:4

            """)
    }

    @Test("checked checkbox-only task list item line with a tab separator")
    func checkedCheckboxOnlyTaskItemTabSeparator() {
        #expect(TreeDump.dump("- [x]\t\nx", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                tasklist checked @1:1-2:2
                  paragraph @2:1-2:2
                    text "x" @2:1-2:2

            """)
    }

    @Test("a checkbox-only item in a block quote is a task list item")
    func blockQuotedCheckboxOnlyItemIsRecognized() {
        #expect(TreeDump.dump("> - [ ] ", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-1:9
              block_quote @1:1-1:8
                list bullet '-' tight @1:3-1:8
                  tasklist unchecked @1:3-1:8

            """)
    }

    @Test("a nested checkbox-only item on the outer item's first line is a task list item")
    func nestedCheckboxOnlyItemIsRecognized() {
        #expect(TreeDump.dump("- - [ ] ", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-1:9
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  list bullet '-' tight @1:3-1:8
                    tasklist unchecked @1:3-1:8

            """)
    }
}
