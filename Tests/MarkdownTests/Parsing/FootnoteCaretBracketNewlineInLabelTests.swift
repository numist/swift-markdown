/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `[^[` footnote collapse whose trailing bracket pair spans a line ending.
///
/// Ground truth is cmark-gfm (flag-ON). In `[^[][` LF `]]` cmark's `[^[` collapse reproduces only `[^[` and
/// drops the rest of the paragraph; a trailing bracket with no line ending inside (`[^[][ ]]`) yields the same `[^[`.
/// Position-free compare surface.
class FootnoteCaretBracketNewlineInLabelTests: XCTestCase {
    private func surface(_ markdown: String, optionBits: UInt8 = 0xc0) -> String {
        var options = ParseOptions(rawValue: UInt(optionBits & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static let collapsed = "Document\n└─ Paragraph\n   └─ Text \"[^[\""

    func testFuzzedArtifact() {
        XCTAssertEqual(Self.collapsed, surface("[^[][\n]]"))
        XCTAssertEqual(Self.collapsed, surface("[^[][\n]]", optionBits: 0xf7))
    }

    func testContentAfterNewline() {
        XCTAssertEqual(Self.collapsed, surface("[^[][\nx]]"))
    }

    func testCRLF() {
        XCTAssertEqual(Self.collapsed, surface("[^[][\r\n]]"))
    }

    func testInnerLabelContent() {
        XCTAssertEqual(Self.collapsed, surface("[^[x][\n]]"))
    }

    func testSurroundingText() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a [^[\"", surface("a [^[][\n]] b"))
    }

    func testNoNewlineControl() {
        XCTAssertEqual(Self.collapsed, surface("[^[][ ]]"))
    }

    func testAttributeOpenerDeeperInFootnoteLabel() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a ^[][\n]]\"", surface("[^a ^[][\n]]"))
    }

    func testConsumedLabelFollowedByParens() {
        XCTAssertEqual(Self.collapsed, surface("[^[][\n]()]"))
    }

    func testMultipleNewlinesInConsumedLabel() {
        XCTAssertEqual(Self.collapsed, surface("[^[][a\nb\nc]]"))
    }

    func testBareNewlineAfterConsumedLabelStillResets() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^]\"", surface("[^[][\n]\n]"))
    }

    func testBlockQuote() {
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Text \"[^[\"", surface("> [^[][\n> ]]"))
    }

    func testResolvedImageReferenceLabelInFootnote() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^x ![a][b\nc]]\"", surface("[^x ![a][b\nc]]\n\n[b c]: /u"))
    }
}
