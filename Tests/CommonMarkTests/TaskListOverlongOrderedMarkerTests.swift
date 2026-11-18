/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Over-long ordered marker before a checkbox")
struct TaskListOverlongOrderedMarkerTests {

    private let source = "10.\n\t1234567890. [ ] x\n"

    @Test("without tasklist, a ten-digit ordered marker is paragraph text")
    func overlongMarkerIsParagraphTextWithoutTasklist() {
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
