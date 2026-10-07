/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A setext heading whose paragraph opens with a link reference definition followed by a lazy
/// continuation line. Ground truth is cmark-gfm.
class SetextRefdefLazyResidualTests: XCTestCase {
    /// Options byte 0x0a (smart off, symbol links).
    private func surface(_ markdown: String) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    private static func quotedHeading(level: Int = 1, _ children: String) -> String {
        "Document\n└─ BlockQuote\n   └─ Heading level: \(level)\n\(children)"
    }

    /// Flag-off (shipped) strips a heading's leading whitespace, as the spec requires.
    func testLazyTwoSpacesFlagOff() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), surface(">[a]:u\n  b\n>=\n"))
    }

    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the lazy line's leading tab.
    func testLazyTabFlagOff() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), surface(">[a]:u\n\tb\n>=\n"))
    }

    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the first remainder line's leading space.
    func testMultiLineRemainderFlagOff() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \"b\"\n      ├─ SoftBreak\n      └─ Text \"c\""),
            surface(">[a]:u\n b\n c\n>=\n"))
    }

    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the lazy line's leading space under a `---` underline.
    func testDashUnderlineFlagOff() {
        XCTAssertEqual(Self.quotedHeading(level: 2, "      └─ Text \"b\""), surface(">[a]:u\n b\n>---\n"))
    }

    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the lazy line's leading space in a list item.
    func testListLazyResidualFlagOff() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \"b\"",
            surface("- [a]:u\n b\n  =\n"))
    }

    /// Flag-off (shipped): a setext heading's content is stripped of leading whitespace, where cmark-gfm
    /// keeps the space left after the outer `>` prefix match.
    func testNestedQuotePartialPrefixFlagOff() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ BlockQuote\n      └─ Heading level: 1\n         └─ Text \"b\"",
            surface(">>[a]:u\n>  b\n>>=\n"))
    }

    /// `[ ] [a]:u` does not begin with a link reference definition, so it is heading text, and a heading is
    /// not the paragraph a task list item must begin with (spec "Task list items (extension)").
    func testTaskCheckboxThenRefDefFlagOff() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         ├─ Text \"[ ] [a]:u\"\n         ├─ SoftBreak\n         └─ Text \"b\"",
            surface("- [ ] [a]:u\n b\n  =\n"))
    }

    func testNonLazyContinuationFlagOff() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), surface(">[a]:u\n>  b\n>=\n"))
    }

    func testNoRefDefFlagOff() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \"a\"\n      ├─ SoftBreak\n      └─ Text \"b\""),
            surface(">a\n b\n>=\n"))
    }

    /// A heading is not the paragraph a task list item must begin with (spec "Task list items (extension)").
    func testTaskCheckboxGapFlagOff() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \"[ ]  \tb\"",
            surface("- [ ]  \tb\n  =\n"))
    }
}
