/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An ordered list marker has at most nine digits (List items), so in the empty item `10.` the tab-indented
/// line `1234567890. [ ] x` is paragraph text. That paragraph begins with `1234567890.`, not a task list item
/// marker, so the item has no checkbox (Task list items (extension)).
@Suite("Over-long ordered marker before a checkbox")
struct TaskListOverlongOrderedMarkerTests {

    private let source = "10.\n\t1234567890. [ ] x\n"

    @Test("without tasklist, the item has no checkbox")
    func plainItemWithoutTasklist() {
        #expect(TreeDump.dump(source, options: []) == """
            document
              list ordered start=10 delim=period tight
                item
                  paragraph
                    text "1234567890. [ ] x"

            """)
    }

    @Test("with tasklist, the item has no checkbox")
    func plainItemWithTasklist() {
        #expect(TreeDump.dump(source, options: [.tasklist]) == """
            document
              list ordered start=10 delim=period tight
                item
                  paragraph
                    text "1234567890. [ ] x"

            """)
    }
}
