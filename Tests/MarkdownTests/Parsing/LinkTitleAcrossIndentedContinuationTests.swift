/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An inline link whose destination and multi-line title start on an indented continuation line.
///
/// Ground truth is cmark-gfm. `[](` + `(` destination + a single-quoted title spanning two lines with an
/// escaped quote (`'\'` LF `'`) forms a Link with destination `(`, whether the continuation line is
/// unindented (source-contiguous content) or indented (segmented content): cmark's longest-match title
/// scan runs past the first line's closing quote to the second line's.
class LinkTitleAcrossIndentedContinuationTests: XCTestCase {
    private func surface(_ markdown: String, options: ParseOptions = [.cmarkBugCompatibility]) -> String {
        Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testIndentedContinuation() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Link destination: \"(\"", surface("x\n []((\n'\\'\n')"))
    }

    func testFuzzedArtifact() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"<\"\n   ├─ SoftBreak\n   └─ Link destination: \"(\"", surface("<\n []((\n'\\'\n')", options: ParseOptions(rawValue: UInt(0x31 & 0b11011111)).union(.cmarkBugCompatibility)))
    }

    // Images print their title, so these probes pin the title's cross-line extent, not only the link's
    // existence. Each sibling's expected tree is its unindented (single-segment) twin's output.

    func testDoubleQuotedTitleWithEscapedCloser() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"(\" title: \"\"\n\"", surface("x\n ![]((\n\"\\\"\n\")"))
    }

    func testParenthesizedTitleWithEscapedCloser() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"(\" title: \")\n\"", surface("x\n ![]((\n(\\)\n))"))
    }

    func testEscapedParenDestination() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"(\" title: \"'\n\"", surface("x\n ![](\\(\n'\\'\n')"))
    }

    func testTitleSpanningThreeLines() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Image source: \"a\" title: \"'\nb\n\"", surface("x\n ![](a\n'\\'\nb\n')"))
    }

    func testBlockQuoteContainer() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      └─ Link destination: \"(\"", surface("> x\n> []((\n> '\\'\n> ')"))
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      └─ Image source: \"(\" title: \"'\n\"", surface("> x\n> ![]((\n> '\\'\n> ')"))
    }

    /// cmark's `<…>` destination scan (`manual_scan_link_url`) skips the byte after any `\`, so a `\` at a
    /// line end carries the destination across the newline.
    func testPointyDestinationWithBackslashAtLineEnd() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Link destination: \"a\\\nb\"", surface("x\n [](<a\\\nb>)"))
    }

    /// The longest-match title runs past a first-line `')` to a later quote with no `)` after it, so no link
    /// forms, as for the unindented twin.
    func testLongestTitleWithoutCloserIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](a ’')\"\n   ├─ SoftBreak\n   └─ Text \"’\"", surface("x\n [](a '\\')\n'"))
    }

    /// An unescaped line ending ends a `<…>` destination scan across a join, as for the unindented twin.
    func testPointyDestinationWithBareLineEndIsNotALink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   ├─ Text \"[](\"\n   ├─ InlineHTML <a\nb>\n   └─ Text \")\"", surface("x\n [](<a\nb>)"))
    }

    func testUnindentedControl() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"<\"\n   ├─ SoftBreak\n   └─ Link destination: \"(\"", surface("<\n[]((\n'\\'\n')"))
    }
}
