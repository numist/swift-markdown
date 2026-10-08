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
class TasklistTableInterruptTests: XCTestCase {
    /// The paragraph before the table starts after the checkbox, also when its lines end in CRLF.
    func testSplitOffParagraphPositions() {
        func paragraphLines(_ markdown: String) -> [String] {
            let dump = Document(parsing: markdown, options: []).debugDescription(options: [.printSourceLocations])
            // The paragraph's lines precede the table, whose cells hold text of their own.
            let beforeTable = dump.split(separator: "\n").map(String.init).prefix { !$0.contains("Table") }
            return beforeTable.filter { $0.contains("Paragraph") || $0.contains("Text @") }
        }
        XCTAssertEqual([
            "      ├─ Paragraph @1:7-1:8",
            "      │  └─ Text @1:7-1:8 \"a\"",
        ], paragraphLines("- [x] a\n  b|\n  -|"))
        XCTAssertEqual([
            "      ├─ Paragraph @1:7-2:4",
            "      │  ├─ Text @1:7-1:8 \"a\"",
            "      │  └─ Text @2:3-2:4 \"b\"",
        ], paragraphLines("- [x] a\r\n  b\r\n  c|\r\n  -|"))
    }
}
