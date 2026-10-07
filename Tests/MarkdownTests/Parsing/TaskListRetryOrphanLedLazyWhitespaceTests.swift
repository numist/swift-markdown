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
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool = true) -> String {
        let (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: cmarkBugCompatible ? options.union(.cmarkBugCompatibility) : options).debugDescription(options: [])
    }

    func testNULOrphanLazySpaceCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testNULLineLazySpaceCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode ` `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66], cmarkBugCompatible: false))
    }

    func testMultiByteOrphanLazySpaceCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  `", surface([43, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testMultiByteLineLazySpaceCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"22\u{E9} [x] \"\n         └─ InlineCode ` `", surface([43, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66], cmarkBugCompatible: false))
    }

    func testTabLedLazyLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode ` `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 9, 96, 66]))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testTabLedLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode ` `", surface([43, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 9, 96, 66], cmarkBugCompatible: false))
    }

    func testLazyRetryLineControl() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"\u{fffd} [x] \"\n            └─ InlineCode `  `", surface([45, 32, 62, 32, 97, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote), and the lazy
    /// line keeps its `2` prefix while the next line loses its leading whitespace (CommonMark paragraphs),
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    func testLazyBlockQuoteLineCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ SoftBreak\n            ├─ Text \"2\u{fffd} [x] \"\n            └─ InlineCode ` `", surface([45, 32, 62, 32, 97, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 96, 10, 32, 96, 66], cmarkBugCompatible: false))
    }

    /// `markdown` followed by the options byte `0x42`, as the fuzzer lays out an input.
    private func surface(markdown: String, cmarkBugCompatible: Bool = true) -> String {
        surface(Array(markdown.utf8) + [0x42], cmarkBugCompatible: cmarkBugCompatible)
    }

    private let orphanItem = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n"

    func testTwoSpaceLazyResidualCodeSpan() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode `   `", surface(markdown: " +\n   2\0 [x] `\n  `"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testTwoSpaceLazyLineCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode ` `", surface(markdown: " +\n   2\0 [x] `\n  `", cmarkBugCompatible: false))
    }

    func testLazyLineImageTitle() {
        XCTAssertEqual(orphanItem + "         └─ Image source: \"b\" title: \"c\n d\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] ![a](b \"c\n d\")"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs) inside the image title, where cmark's later-line checkbox
    /// retry checks the item and keeps the lazy line's leading whitespace.
    func testLazyLineImageTitleFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ Image source: \"b\" title: \"c\nd\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] ![a](b \"c\n d\")", cmarkBugCompatible: false))
    }

    func testLazyLineLinkDestinationControl() {
        XCTAssertEqual(orphanItem + "         └─ Link destination: \"b\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] [a](\n b)"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the link destination follows the line ending, where cmark's
    /// later-line checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testLazyLineLinkDestinationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ Link destination: \"b\"\n            └─ Text \"a\"", surface(markdown: "+\n  2\0 [x] [a](\n b)", cmarkBugCompatible: false))
    }

    func testSecondLazyLineCodeSpan() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode ` a `", surface(markdown: "+\n  2\0 [x] `\n a\n `"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy lines' leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving the code span `a`, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testSecondLazyLineCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode `a`", surface(markdown: "+\n  2\0 [x] `\n a\n `", cmarkBugCompatible: false))
    }

    func testMatchedContinuationControl() {
        XCTAssertEqual(orphanItem + "         └─ InlineCode ` `", surface(markdown: "+\n  2\0 [x] `\n   `"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the continuation line's extra indent is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testMatchedContinuationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode ` `", surface(markdown: "+\n  2\0 [x] `\n   `", cmarkBugCompatible: false))
    }

    func testLazyResidualAfterSoftBreakLeavesText() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface(markdown: "+\n  2\0 [x] a\n b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), where cmark's later-line checkbox retry checks the item
    /// and keeps the lazy line's leading whitespace.
    func testLazyLineAfterSoftBreakFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] a\"\n         ├─ SoftBreak\n         └─ Text \"b\"", surface(markdown: "+\n  2\0 [x] a\n b", cmarkBugCompatible: false))
    }

    func testLazyResidualAfterBackslashBreakStaysText() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] a\"\n         ├─ LineBreak\n         └─ Text \" b\"", surface(markdown: "+\n  2\0 [x] a\\\n b"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs) after the hard line break, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testLazyLineAfterBackslashBreakFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] a\"\n         ├─ LineBreak\n         └─ Text \"b\"", surface(markdown: "+\n  2\0 [x] a\\\n b", cmarkBugCompatible: false))
    }

    func testTabLazyResidualCodeSpan() {
        XCTAssertEqual("Document\n└─ OrderedList startIndex: 100\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"\u{fffd} [x] \"\n         └─ InlineCode `  \t`", surface(markdown: "100.\n     2\0 [x] `\n \t`"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testTabLazyLineCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ OrderedList startIndex: 100\n   └─ ListItem\n      └─ Paragraph\n         ├─ Text \"2\u{fffd} [x] \"\n         └─ InlineCode ` `", surface(markdown: "100.\n     2\0 [x] `\n \t`", cmarkBugCompatible: false))
    }

    func testSplitTabLazyResidualCodeSpan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ OrderedList startIndex: 100\n         └─ ListItem checkbox: [x]\n            └─ Paragraph\n               ├─ Text \"\u{fffd} [x] \"\n               └─ InlineCode `   `", surface(markdown: "+ 100.\n       2\0 [x] `\n \t`"))
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    func testSplitTabLazyLineCodeSpanFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ OrderedList startIndex: 100\n         └─ ListItem\n            └─ Paragraph\n               ├─ Text \"2\u{fffd} [x] \"\n               └─ InlineCode ` `", surface(markdown: "+ 100.\n       2\0 [x] `\n \t`", cmarkBugCompatible: false))
    }

}
