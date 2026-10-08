/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// When a task list item's first line holds only its task list item marker, a `[x]` on the next line is
/// paragraph text (Task list items (extension)).
class TaskListEmptyCheckboxLineContinuationTests: XCTestCase {
    // "- [x] " LF "  [x]"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x78, 0x5d, 0x20, 0x0a, 0x20, 0x20, 0x5b, 0x78, 0x5d]
    private static let options = ParseOptions(rawValue: UInt(0x20 & 0b11011111))

    private func surface() -> String {
        Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: Self.options)
            .debugDescription(options: [])
    }

    func testBracketContinuationKeptAsParagraph() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[x]\""
        XCTAssertEqual(expected, surface())
    }
}
