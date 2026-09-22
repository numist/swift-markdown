/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// cmark's task-list checkbox recognition on a lazy list-item continuation line whose content is
/// `<digits> [ ] ` (a digit run, a space, a checkbox, and a trailing space).
///
/// Ground truth is cmark-gfm. For `-` / `  22 [ ] ` cmark produces a task item — `ListItem checkbox: [ ]`
/// with paragraph text `[ ]` — even though the content does not begin with the checkbox (it begins with
/// `22`). This does not happen without the digit prefix (`-` / `  [ ] ` matches on both sides with no
/// checkbox), without the trailing space, or when the same content is on the item's opening line — so it is
/// a cmark quirk of this specific lazy-continuation shape. The spec-correct parse (flag-off) keeps the whole
/// line as paragraph text with no checkbox. Flag-on reproduces cmark; flag-off stays spec-correct.
/// Position-free surface.
class TaskListDigitPrefixCheckboxTests: XCTestCase {
    // "-" LF "  22 [ ] "
    private static let bytes: [UInt8] = [0x2d, 0x0a, 0x20, 0x20, 0x32, 0x32, 0x20, 0x5b, 0x20, 0x5d, 0x20]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Flag-on: reproduce cmark's quirky checkbox.
    func testFlagOnRecognizesCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Paragraph\n         └─ Text \"[ ]\"",
            surface(cmarkBugCompatible: true))
    }

    /// Flag-off (spec-correct): no checkbox — the whole continuation line stays paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"22 [ ]\"",
            surface(cmarkBugCompatible: false))
    }
}
