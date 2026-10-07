/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An empty ordered item `10.` followed by a tab-indented line `1234567890. [ ] x`. cmark's tasklist extension scans the
/// continuation line from its start, where an over-long ordered marker and a checkbox follow the tab, and turns the item
/// into a task item, consuming three bytes of the line content (extensions/tasklist.c, `open_tasklist_item`).
/// The rewrite keeps the spec-correct plain item: a checkbox counts
/// only on the item's own opening line, so the line is ordinary paragraph text, where cmark still makes a task item.
@Suite("Task item retry on a tab-expanded line")
struct TaskListRetryTabExpandedLineTests {

    private let source = "10.\n\t1234567890. [ ] x\n"

    @Test("without tasklist or cmark bug compatibility, the item stays a plain item")
    func plainItemWithoutTasklistOrBugCompatibility() {
        #expect(CmarkTreeDump.dump(source, options: []) == """
            document
              list ordered start=10 delim=period tight
                item
                  paragraph
                    text "1234567890. [ ] x"

            """)
    }

    /// The rewrite intentionally keeps the plain item.
    @Test("without cmark bug compatibility, the item stays a plain item")
    func plainItemWithoutBugCompatibility() {
        #expect(CmarkTreeDump.dump(source, options: [.tasklist]) == """
            document
              list ordered start=10 delim=period tight
                item
                  paragraph
                    text "1234567890. [ ] x"

            """)
    }
}
