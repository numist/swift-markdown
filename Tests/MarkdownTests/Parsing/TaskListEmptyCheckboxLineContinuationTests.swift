/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A task list item whose first line is only the checkbox (empty content plus a trailing space), continued
/// by a line whose content is itself bracket-shaped (`[x]`).
///
/// Ground truth is cmark-gfm. For `- [x] ` / `  [x]` the item's checkbox comes from the first line and the
/// continuation line `[x]` is the item's paragraph text. The rewrite instead mis-attributed the
/// continuation line's `[x]` as the checkbox and dropped it, leaving an EMPTY item. A plain-text
/// continuation (`  y`), a first line without the trailing space, and a non-task first line all behave
/// correctly — only the empty-checkbox-line + bracket-shaped-continuation combination broke. Keeping the
/// continuation as content is spec-correct, so both flag states must. Position-free compare surface.
class TaskListEmptyCheckboxLineContinuationTests: XCTestCase {
    // "- [x] " LF "  [x]"
    private static let bytes: [UInt8] = [0x2d, 0x20, 0x5b, 0x78, 0x5d, 0x20, 0x0a, 0x20, 0x20, 0x5b, 0x78, 0x5d]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x20 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testBracketContinuationKeptAsParagraph() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[x]\""
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(cmarkBugCompatible: false))
    }
}
