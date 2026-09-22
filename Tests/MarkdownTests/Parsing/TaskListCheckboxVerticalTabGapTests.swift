/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A task-list checkbox reached past a vertical-tab gap after the list marker, with a trailing space and a
/// continuation line.
///
/// Ground truth is cmark-gfm. For `- ` VT `[x] ` then a continuation line `` ` ``, cmark recognizes the
/// checkbox `[x]` (the VT gap notwithstanding), leaving `]` as the item's paragraph text joined by a soft
/// break to the continuation backtick. The rewrite's flag-off path already matches cmark, but its
/// `.cmarkBugCompatibility` path missed the checkbox (kept `[x]` literal) for this VT + trailing-space +
/// continuation-line combination. Recognizing the checkbox is spec-correct and cmark agrees, so both flag
/// states must. Position-free compare surface.
class TaskListCheckboxVerticalTabGapTests: XCTestCase {
    // "- " VT "[x] " LF "`"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x0b, 0x5b, 0x78, 0x5d, 0x20, 0x0a, 0x60]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x3c & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testCheckboxRecognizedPastVerticalTabGap() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"]\"\n         ├─ SoftBreak\n         └─ Text \"`\""
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(cmarkBugCompatible: false))
    }
}
