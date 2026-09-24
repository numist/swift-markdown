/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An uppercase `[X]` on a childless item's later digit-prefixed line is recognized like `[x]`.
///
/// Ground truth is cmark-gfm (flag-ON). cmark's `open_tasklist_item` retries on a childless item's later
/// line, where its `[0-9]+.` pattern lets the byte after the digits be any character (see
/// `TaskListDigitPrefixCheckboxTests`). The lowercase `[x]` form already matches; the uppercase `[X]` form
/// must set `checkbox: [x]` the same way. Position-free compare surface.
class TaskListDigitPrefixUppercaseCheckboxTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility]).debugDescription(options: [])
    }

    func testUppercaseCheckboxThenTab() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[X]\"", surface("+\n  2- [X]\t"))
    }

    func testUppercaseCheckboxThenContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[X] a\"", surface("+\n  2- [X] a"))
    }

    func testMultiDigitUppercaseCheckbox() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[X]\"", surface("+\n  12- [X]\t"))
    }

    /// The `[0-9]+.` wildcard consumes one UTF-8 scalar, not one byte (`ext_scanners.c` decodes a
    /// multi-byte sequence there), so a 2-byte scalar after the digit still leaves the space the pattern needs.
    func testMultiByteScalarAfterDigit() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"[x]\"", surface("+\n  2\u{E9} [x] "))
    }

    /// Flag-off (spec-correct): no checkbox; the whole continuation line stays paragraph text.
    func testFlagOffNoCheckbox() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         └─ Text \"2- [X]\"",
            Document(parsing: "+\n  2- [X]\t").debugDescription(options: []))
    }
}
