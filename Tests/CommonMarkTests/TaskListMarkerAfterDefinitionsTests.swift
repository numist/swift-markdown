/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A link reference definition counts as a block of its list item, as it does for list looseness (Lists), so a task
/// list item marker after an item's leading definitions doesn't begin the item's first block, and the item is no
/// task list item (Task list items (extension)).
@Suite("Task list item marker after a list item's definitions")
struct TaskListMarkerAfterDefinitionsTests {

    @Test("a marker on the definition's paragraph's next line is text")
    func markerOnNextLine() {
        #expect(TreeDump.dump("- [a]: /u\n  [ ] foo\n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:10
                item @1:1-2:10
                  paragraph @2:3-2:10
                    text "[ ] foo" @2:3-2:10

            """)
    }

    @Test("a marker after a line tabulation is text")
    func markerAfterLineTabulation() {
        #expect(TreeDump.dump("- [a]: /u\n  \u{0B}[ ] b\n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:9
                item @1:1-2:9
                  paragraph @2:4-2:9
                    text "[ ] b" @2:4-2:9

            """)
    }

    @Test("a marker after a form feed before a table is text")
    func markerAfterFormFeedBeforeTable() {
        #expect(TreeDump.dump("- [a]: /u\n  \u{0C}[x] b\n  h|i\n  -|-\n", options: [.tasklist, .tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:6
                item @1:1-4:6
                  paragraph @2:4-2:9
                    text "[x] b" @2:4-2:9
                  table @3:3-4:6
                    table_header @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "h" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "i" @3:5-3:6

            """)
    }

    @Test("a marker beginning a paragraph after the definitions and a blank line is text")
    func markerAfterBlankLine() {
        #expect(TreeDump.dump("- [a]: /u\n\n  [ ] foo\n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:1
              list bullet '-' loose @1:1-3:10
                item @1:1-3:10
                  paragraph @3:3-3:10
                    text "[ ] foo" @3:3-3:10

            """)
    }

    @Test("without tasklist, a line tabulation after the definitions is not the paragraph's text")
    func markerAfterLineTabulationWithoutTasklist() {
        #expect(TreeDump.dump("- [a]: /u\n  \u{0B}[ ] b\n", options: []) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "[ ] b"

            """)
    }
}
