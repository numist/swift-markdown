/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A setext heading whose paragraph opens with a link reference definition followed by a lazy
/// continuation line. Ground truth is cmark-gfm.
///
/// A lazy continuation keeps its leading whitespace in cmark's paragraph content (`add_line` copies from
/// where prefix matching stopped). The setext branch resolves the ref-def through its newline, so that
/// residual leads the heading content, and heading inlines are only right-trimmed: it stays literal text.
class SetextRefdefLazyResidualTests: XCTestCase {
    /// Options byte 0x0a (smart off, symbol links).
    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true) -> String {
        var bytes = Array(markdown.utf8)
        bytes.append(0x0a)
        let (text, fuzzedOptions) = FuzzRegressionTests.splitInput(bytes)!
        var options = fuzzedOptions
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: text, options: options).debugDescription(options: [])
    }

    private static func quotedHeading(level: Int = 1, _ children: String) -> String {
        "Document\n└─ BlockQuote\n   └─ Heading level: \(level)\n\(children)"
    }

    func testLazyTwoSpacesAreKept() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"  b\""), surface(">[a]:u\n  b\n>=\n"))
    }

    func testLazyTabIsKept() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"\tb\""), surface(">[a]:u\n\tb\n>=\n"))
    }

    /// Only the remainder's first line leads the content; later lines' residual is inline whitespace
    /// after a soft break, which text flow skips.
    func testMultiLineRemainderKeepsOnlyLeadingResidual() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \" b\"\n      ├─ SoftBreak\n      └─ Text \"c\""),
            surface(">[a]:u\n b\n c\n>=\n"))
    }

    func testDashUnderlineKeepsResidual() {
        XCTAssertEqual(Self.quotedHeading(level: 2, "      └─ Text \" b\""), surface(">[a]:u\n b\n>---\n"))
    }

    func testListLazyResidualIsKept() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem\n      └─ Heading level: 1\n         └─ Text \" b\"",
            surface("- [a]:u\n b\n  =\n"))
    }

    /// The residual is measured from where the outer `>` prefix match stopped.
    func testNestedQuotePartialPrefixResidualIsKept() {
        XCTAssertEqual(
            "Document\n└─ BlockQuote\n   └─ BlockQuote\n      └─ Heading level: 1\n         └─ Text \" b\"",
            surface(">>[a]:u\n>  b\n>>=\n"))
    }

    /// The checkbox is consumed at item open, then the ref-def, leaving the lazy residual.
    func testTaskCheckboxThenRefDefKeepsResidual() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Heading level: 1\n         └─ Text \" b\"",
            surface("- [ ] [a]:u\n b\n  =\n"))
    }

    /// A matched continuation is advanced to its first non-space, so no residual reaches the content.
    func testNonLazyContinuationDropsWhitespace() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), surface(">[a]:u\n>  b\n>=\n"))
    }

    /// Without a ref-def the residual follows a soft break, which text flow skips.
    func testNoRefDefDropsResidual() {
        XCTAssertEqual(
            Self.quotedHeading("      ├─ Text \"a\"\n      ├─ SoftBreak\n      └─ Text \"b\""),
            surface(">a\n b\n>=\n"))
    }

    /// cmark's paragraph opens at the first non-space after the checkbox, so the gap is not a residual.
    func testTaskCheckboxGapIsNotResidual() {
        XCTAssertEqual(
            "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Heading level: 1\n         └─ Text \"b\"",
            surface("- [ ]  \tb\n  =\n"))
    }

    /// Flag-off (shipped) strips a heading's leading whitespace, as the spec requires.
    func testLazyTwoSpacesFlagOff() {
        XCTAssertEqual(Self.quotedHeading("      └─ Text \"b\""), surface(">[a]:u\n  b\n>=\n", cmarkBugCompatible: false))
    }
}
