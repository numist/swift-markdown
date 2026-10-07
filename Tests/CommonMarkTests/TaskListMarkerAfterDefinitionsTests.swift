/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph's leading link reference definitions are not part of its content, so the task list item
/// marker check applies to what follows them, once its initial whitespace is removed (spec "Paragraphs").
@Suite("Task list item marker after a paragraph's definitions")
struct TaskListMarkerAfterDefinitionsTests {

    @Test("a marker after a line tabulation makes a task item")
    func markerAfterLineTabulation() {
        #expect(CmarkTreeDump.dump("- [a]: /u\n  \u{0B}[ ] b\n", options: [.tasklist, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:9
              list bullet '-' tight @1:1-2:9
                tasklist unchecked @1:1-2:9
                  paragraph @2:8-2:9
                    text "b" @2:8-2:9

            """)
    }

    @Test("a marker after a form feed makes a task item before a table")
    func markerAfterFormFeedBeforeTable() {
        #expect(CmarkTreeDump.dump("- [a]: /u\n  \u{0C}[x] b\n  h|i\n  -|-\n", options: [.tasklist, .tables, .sourcePosition], sourceRanges: true) == """
            document @1:1-4:6
              list bullet '-' tight @1:1-4:6
                tasklist checked @1:1-4:6
                  paragraph @2:8-2:9
                    text "b" @2:8-2:9
                  table @3:3-4:6
                    table_header @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "h" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "i" @3:5-3:6

            """)
    }

    @Test("without tasklist, the marker is text")
    func markerAfterLineTabulationWithoutTasklist() {
        #expect(CmarkTreeDump.dump("- [a]: /u\n  \u{0B}[ ] b\n", options: []) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "[ ] b"

            """)
    }
}
