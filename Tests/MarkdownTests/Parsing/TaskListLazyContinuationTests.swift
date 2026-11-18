/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// Only paragraph continuation text can be a lazy continuation line (List items), so `z` ends the list instead of
// becoming a row of the item's table.
class TaskListLazyContinuationTests: XCTestCase {
    func testUnindentedLineAfterTableInItemIsParagraphAfterList() {
        XCTAssertEqual(
            "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ Table alignments: |-|\n│        ├─ Head\n│        │  └─ Cell\n│        │     └─ Text \"[ ]\"\n│        └─ Body\n└─ Paragraph\n   └─ Text \"z\"",
            Document(parsing: "- [ ] |\n  -|\nz").debugDescription(options: []))
    }
}
