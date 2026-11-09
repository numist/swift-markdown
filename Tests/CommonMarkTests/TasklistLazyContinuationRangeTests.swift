/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph continuation line in a task list item has a source range that starts at the line's first content byte,
/// whatever the width of the checkbox on the opening line, and ends after the line's last content byte.
@Suite("Task list item continuation line source ranges")
struct TasklistLazyContinuationRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.tasklist, .sourcePosition]

    @Test("an unchecked task list item's lazy continuation line starts at column 1")
    func uncheckedLazyContinuationColumn() {
        #expect(TreeDump.dump("- [ ] x\ny", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                tasklist unchecked @1:1-2:2
                  paragraph @1:7-2:2
                    text "x" @1:7-1:8
                    softbreak @-
                    text "y" @2:1-2:2

            """)
        #expect(TreeDump.dump("- [ ] x\nyyyyyyyyyy", options: Self.options, sourceRanges: true) == """
            document @1:1-2:11
              list bullet '-' tight @1:1-2:11
                tasklist unchecked @1:1-2:11
                  paragraph @1:7-2:11
                    text "x" @1:7-1:8
                    softbreak @-
                    text "yyyyyyyyyy" @2:1-2:11

            """)
    }

    @Test("a checked task list item's lazy continuation line starts at column 1")
    func checkedLazyContinuationColumn() {
        #expect(TreeDump.dump("- [x] x\ny", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                tasklist checked @1:1-2:2
                  paragraph @1:7-2:2
                    text "x" @1:7-1:8
                    softbreak @-
                    text "y" @2:1-2:2

            """)
        #expect(TreeDump.dump("- [x] x\nyyyyyyyyyy", options: Self.options, sourceRanges: true) == """
            document @1:1-2:11
              list bullet '-' tight @1:1-2:11
                tasklist checked @1:1-2:11
                  paragraph @1:7-2:11
                    text "x" @1:7-1:8
                    softbreak @-
                    text "yyyyyyyyyy" @2:1-2:11

            """)
    }

    @Test("a one-space-indented continuation line starts after the space")
    func oneSpaceContinuationColumn() {
        #expect(TreeDump.dump("- [ ] x\n y", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              list bullet '-' tight @1:1-2:3
                tasklist unchecked @1:1-2:3
                  paragraph @1:7-2:3
                    text "x" @1:7-1:8
                    softbreak @-
                    text "y" @2:2-2:3

            """)
        #expect(TreeDump.dump("- [ ] x\n yyyyyyyyyy", options: Self.options, sourceRanges: true) == """
            document @1:1-2:12
              list bullet '-' tight @1:1-2:12
                tasklist unchecked @1:1-2:12
                  paragraph @1:7-2:12
                    text "x" @1:7-1:8
                    softbreak @-
                    text "yyyyyyyyyy" @2:2-2:12

            """)
    }

    @Test("a four-space-indented continuation line starts after the spaces")
    func fourSpaceContinuationColumn() {
        #expect(TreeDump.dump("- [ ] x\n    y", options: Self.options, sourceRanges: true) == """
            document @1:1-2:6
              list bullet '-' tight @1:1-2:6
                tasklist unchecked @1:1-2:6
                  paragraph @1:7-2:6
                    text "x" @1:7-1:8
                    softbreak @-
                    text "y" @2:5-2:6

            """)
        #expect(TreeDump.dump("- [ ] x\n    yyyyyyyyyy", options: Self.options, sourceRanges: true) == """
            document @1:1-2:15
              list bullet '-' tight @1:1-2:15
                tasklist unchecked @1:1-2:15
                  paragraph @1:7-2:15
                    text "x" @1:7-1:8
                    softbreak @-
                    text "yyyyyyyyyy" @2:5-2:15

            """)
    }
}
