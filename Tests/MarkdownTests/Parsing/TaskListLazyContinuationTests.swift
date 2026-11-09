/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// In `- [ ] |` / `  -|` / `z`, the item's first block is a one-column table, so the item is not a task list
/// item (Task list items (extension)). A table has no lazy continuation lines, so `z` is a paragraph after
/// the list.
class TaskListLazyContinuationTests: XCTestCase {
    func testUnindentedLineAfterTableInItemIsParagraphAfterList() {
        XCTAssertEqual(
            "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ Table alignments: |-|\n│        ├─ Head\n│        │  └─ Cell\n│        │     └─ Text \"[ ]\"\n│        └─ Body\n└─ Paragraph\n   └─ Text \"z\"",
            Document(parsing: "- [ ] |\n  -|\nz").debugDescription(options: []))
    }
}
