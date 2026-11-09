/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task list item's checked state comes from its leading checkbox alone (Task list items (extension)); a
/// later `[x]` on the same line is paragraph text.
@Suite("Task list item checked state")
struct TaskListCheckedStateTests {

    @Test("`- [ ] [x]` is unchecked")
    func laterCheckedBoxIgnored() {
        #expect(TreeDump.dump("- [ ] [x]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[x]"

            """)
    }

    @Test("`- [ ] x [x] y` is unchecked")
    func midLineCheckedBoxIgnored() {
        #expect(TreeDump.dump("- [ ] x [x] y", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "x [x] y"

            """)
    }

    @Test("`- [ ] [X]` is unchecked")
    func laterUppercaseCheckedBoxIgnored() {
        #expect(TreeDump.dump("- [ ] [X]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[X]"

            """)
    }

    @Test("`- [x] [ ]` is checked")
    func leadingCheckedBoxBeforeUncheckedBox() {
        #expect(TreeDump.dump("- [x] [ ]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "[ ]"

            """)
    }

    @Test("`- [x] foo` is checked")
    func checkedWithContent() {
        #expect(TreeDump.dump("- [x] foo", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "foo"

            """)
    }

    @Test("`- [ ]   foo [x]` is unchecked with several spaces after the checkbox")
    func multiSpaceAfterCheckbox() {
        #expect(TreeDump.dump("- [ ]   foo [x]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "foo [x]"

            """)
    }

    @Test("`- [ ] a [X] b` is unchecked")
    func uppercaseMidLineIgnored() {
        #expect(TreeDump.dump("- [ ] a [X] b", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a [X] b"

            """)
    }

    @Test("`- [ ] [x` is unchecked")
    func noClosingBracket() {
        #expect(TreeDump.dump("- [ ] [x", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[x"

            """)
    }

    @Test("`- [ ] (x)` is unchecked")
    func parens() {
        #expect(TreeDump.dump("- [ ] (x)", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "(x)"

            """)
    }

    @Test("`- [ ] ]x[` is unchecked")
    func reversedBrackets() {
        #expect(TreeDump.dump("- [ ] ]x[", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "]x["

            """)
    }

    @Test("continuation-line `[x]` does not check the item")
    func continuationLineCheckedBoxIgnored() {
        #expect(TreeDump.dump("- [ ] a\n  [x]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a"
                    softbreak
                    text "[x]"

            """)
    }

    @Test("`- [ ] [ ]` is unchecked")
    func bothUnchecked() {
        #expect(TreeDump.dump("- [ ] [ ]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "[ ]"

            """)
    }

    @Test("`- [x] [x]` is checked")
    func bothChecked() {
        #expect(TreeDump.dump("- [x] [x]", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "[x]"

            """)
    }

    @Test("`- [ ] x` is unchecked")
    func plainContent() {
        #expect(TreeDump.dump("- [ ] x", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "x"

            """)
    }
}
