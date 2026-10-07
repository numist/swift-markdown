/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A task-list checkbox reached past a vertical-tab gap after the list marker, with a trailing space and a
/// continuation line.
///
/// Ground truth is cmark-gfm. For `- ` VT `[x] ` then a continuation line `` ` ``, cmark recognizes the
/// checkbox `[x]` (the VT gap notwithstanding), leaving `]` as the item's paragraph text joined by a soft
/// break to the continuation backtick. Recognizing the checkbox is spec-correct and cmark agrees.
/// Position-free compare surface.
class TaskListCheckboxVerticalTabGapTests: XCTestCase {
    // "- " VT "[x] " LF "`"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x0b, 0x5b, 0x78, 0x5d, 0x20, 0x0a, 0x60]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x3c & 0b11011111))

    private func surface() -> String {
        Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: Self.fuzzedBits)
            .debugDescription(options: [])
    }

    func testCheckboxRecognizedPastVerticalTabGap() {
        // The paragraph's initial line tabulation is removed (spec "Paragraphs"), so it begins with the
        // marker, and its content is what follows the marker's whitespace.
        let shipped = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"`\""
        XCTAssertEqual(shipped, surface())
    }
}
