/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// A lazy continuation line of an orphan-led (first-line tasklist retry) paragraph keeps its leading
/// whitespace, so a code span spanning it keeps that space. Expected surfaces are the cmark-gfm reference's
/// output bytes; inputs are `[markdown …][option byte]`, split as the fuzzer does.
class TaskListRetryOrphanLedLazyWhitespaceTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: options.union(.cmarkBugCompatibility)).debugDescription(options: [])
    }

    func testNULOrphanLazySpaceCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    func testMultiByteOrphanLazySpaceCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  `", surface([43, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    func testTabLedLazyLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode ` `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 9, 96, 66]))
    }

    func testLazyRetryLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{fffd} [x] \"\n            └─ InlineCode `  `", surface([45, 32, 62, 32, 97, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    /// `markdown` followed by the options byte `0x42`, as the fuzzer lays out an input.
    private func surface(markdown: String) -> String {
        surface(Array(markdown.utf8) + [0x42])
    }

    private let orphanItem = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n"

    func testTwoSpaceLazyResidualCodeSpan() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode `   `", surface(markdown: " +\n   2\0 [x] `\n  `"))
    }

    func testLazyLineImageTitle() {
        XCTAssertEqual(orphanItem + "         └─ Image source: \"b\" title: \"c\n d\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] ![a](b \"c\n d\")"))
    }

    func testLazyLineLinkDestinationControl() {
        XCTAssertEqual(orphanItem + "         └─ Link destination: \"b\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] [a](\n b)"))
    }

    func testSecondLazyLineCodeSpan() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode ` a `", surface(markdown: "+\n  2\0 [x] `\n a\n `"))
    }

    func testMatchedContinuationControl() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode ` `", surface(markdown: "+\n  2\0 [x] `\n   `"))
    }

    func testLazyResidualAfterSoftBreakLeavesText() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface(markdown: "+\n  2\0 [x] a\n b"))
    }

    func testLazyResidualAfterBackslashBreakStaysText() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] a\"\n         ├─ LineBreak\n         └─ Text \" b\"", surface(markdown: "+\n  2\0 [x] a\\\n b"))
    }

    func testTabLazyResidualCodeSpan() {
        XCTAssertEqual("Document\n└─ OrderedList startIndex: 100\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  \t`", surface(markdown: "100.\n     2\0 [x] `\n \t`"))
    }

    func testSplitTabLazyResidualCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ OrderedList startIndex: 100\n         └─ ListItem checkbox: [x]\n            └─ Paragraph\n               ├─ Text \"\u{fffd} [x] \"\n               └─ InlineCode `   `", surface(markdown: "+ 100.\n       2\0 [x] `\n \t`"))
    }

}
