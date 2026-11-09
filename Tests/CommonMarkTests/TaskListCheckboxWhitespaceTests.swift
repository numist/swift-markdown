/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A task list item marker holds a whitespace character or an `x` between its brackets, and a whitespace character
/// makes the checkbox unchecked (Task list items (extension)).
@Suite("Task list item checkbox holding a whitespace character")
struct TaskListCheckboxWhitespaceTests {

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: .tasklist)
    }

    @Test("a tab")
    func tab() {
        #expect(tree("- [\t] a\n") == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a"

            """)
    }

    @Test("a line tabulation")
    func lineTabulation() {
        #expect(tree("- [\u{0B}] a\n") == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a"

            """)
    }

    @Test("a form feed")
    func formFeed() {
        #expect(tree("- [\u{0C}] a\n") == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a"

            """)
    }
}
