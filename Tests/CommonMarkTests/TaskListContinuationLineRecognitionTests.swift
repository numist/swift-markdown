/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task list item marker begins the item's first paragraph (Task list items (extension)), so it may sit
/// on the line after a list marker with no content.
@Suite("Task list item marker on a continuation line")
struct TaskListContinuationLineRecognitionTests {

    @Test("`-\\n  [x] foo` is a checked task list item")
    func checkboxOnContinuationLine() {
        #expect(TreeDump.dump("-\n  [x] foo", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "foo"

            """)
    }

    @Test("`- [x] foo` is a checked task list item")
    func checkboxOnOpeningLine() {
        #expect(TreeDump.dump("- [x] foo", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "foo"

            """)
    }

    @Test("`- [x] a\\n  [x] b` is a checked task list item")
    func checkboxOnOpeningLineWithContinuation() {
        #expect(TreeDump.dump("- [x] a\n  [x] b", options: [.tasklist]) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                    softbreak
                    text "[x] b"

            """)
    }
}
