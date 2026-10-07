/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A setext heading whose lines begin with a link reference definition and continue on an indented line.
/// As with a paragraph, the heading's content has its initial whitespace removed (Paragraphs, Setext headings).
class SetextRefdefLazyResidualTests: XCTestCase {
    /// Parses `markdown` with `[.parseSymbolLinks, .parseMinimalDoxygen]`.
    private func tree(_ markdown: String) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, options) = DocumentRegressionTests.splitInput(bytes)!
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    private static func quotedHeading(level: Int = 1, _ children: String) -> String {
        "Document\n└─ BlockQuote\n   └─ Heading level: \(level)\n\(children)"
    }

    func testLazyTwoSpaces() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), tree(">[a]:u\n  b\n>=\n"))
    }

    func testLazyTab() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), tree(">[a]:u\n\tb\n>=\n"))
    }

    func testMultiLineRemainder() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \"b\"\n      ├─ SoftBreak\n      └─ Text \"c\""),
            tree(">[a]:u\n b\n c\n>=\n"))
    }

    func testDashUnderline() {
        XCTAssertEqual(Self.quotedHeading(level: 2, "      └─ Text \"b\""), tree(">[a]:u\n b\n>---\n"))
    }

    func testListItemLazyLine() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \"b\"",
            tree("- [a]:u\n b\n  =\n"))
    }

    func testNestedQuotePartialPrefix() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ BlockQuote\n      └─ Heading level: 1\n         └─ Text \"b\"",
            tree(">>[a]:u\n>  b\n>>=\n"))
    }

    /// `[ ] [a]:u` does not begin with a link reference definition, so it is heading text, and a heading is
    /// not the paragraph a task list item must begin with (spec "Task list items (extension)").
    func testTaskCheckboxThenRefDef() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         ├─ Text \"[ ] [a]:u\"\n         ├─ SoftBreak\n         └─ Text \"b\"",
            tree("- [ ] [a]:u\n b\n  =\n"))
    }

    func testNonLazyContinuation() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), tree(">[a]:u\n>  b\n>=\n"))
    }

    func testNoRefDef() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \"a\"\n      ├─ SoftBreak\n      └─ Text \"b\""),
            tree(">a\n b\n>=\n"))
    }

    /// A heading is not the paragraph a task list item must begin with (spec "Task list items (extension)").
    func testTaskCheckboxGap() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \"[ ]  \tb\"",
            tree("- [ ]  \tb\n  =\n"))
    }
}
