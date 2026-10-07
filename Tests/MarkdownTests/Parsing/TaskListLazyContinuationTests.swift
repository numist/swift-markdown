/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// In `- [ ] |` / `  -|` / `z`, the item's first block is a one-column table, so the item is not a task list
/// item (Task list items (extension)). A table has no lazy continuation lines, so `z` is a paragraph after
/// the list.
class TaskListLazyContinuationTests: XCTestCase {
    private func surface(_ bytes: [UInt8], options optionByte: UInt8) -> String {
        let options = ParseOptions(rawValue: UInt(optionByte & 0b11011111))
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testUnindentedLineAfterTableInItemIsParagraphAfterList() {
        let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x20, 0x5d, 0x20, 0x7c, 0x0a, 0x20, 0x20, 0x2d, 0x7c, 0x0a, 0x7a]
        XCTAssertEqual(Self.tableInItem(lastLine: "z"), surface(bytes, options: 0x00))
    }

    private static func tableInItem(lastLine: String) -> String {
        "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ Table alignments: |-|\n│        ├─ Head\n│        │  └─ Cell\n│        │     └─ Text \"[ ]\"\n│        └─ Body\n└─ Paragraph\n   └─ Text \"\(lastLine)\""
    }
}
