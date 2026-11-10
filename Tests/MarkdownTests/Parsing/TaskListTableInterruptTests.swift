/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A task list item whose first paragraph is followed by a table keeps its checkbox.
class TaskListTableInterruptTests: XCTestCase {
    /// The paragraph before the table starts after the checkbox, also when its lines end in CRLF.
    func testSplitOffParagraphPositions() {
        func dump(_ markdown: String) -> String {
            Document(parsing: markdown, options: []).debugDescription(options: [.printSourceLocations])
        }
        XCTAssertEqual("""
            Document @1:1-3:5
            └─ UnorderedList @1:1-3:5
               └─ ListItem @1:1-3:5 checkbox: [x]
                  ├─ Paragraph @1:7-1:8
                  │  └─ Text @1:7-1:8 "a"
                  └─ Table @2:3-3:5 alignments: |-|
                     ├─ Head @2:3-2:5
                     │  └─ Cell @2:3-2:4
                     │     └─ Text @2:3-2:4 "b"
                     └─ Body
            """, dump("- [x] a\n  b|\n  -|"))
        XCTAssertEqual("""
            Document @1:1-4:5
            └─ UnorderedList @1:1-4:5
               └─ ListItem @1:1-4:5 checkbox: [x]
                  ├─ Paragraph @1:7-2:4
                  │  ├─ Text @1:7-1:8 "a"
                  │  ├─ SoftBreak
                  │  └─ Text @2:3-2:4 "b"
                  └─ Table @3:3-4:5 alignments: |-|
                     ├─ Head @3:3-3:5
                     │  └─ Cell @3:3-3:4
                     │     └─ Text @3:3-3:4 "c"
                     └─ Body
            """, dump("- [x] a\r\n  b\r\n  c|\r\n  -|"))
    }
}
