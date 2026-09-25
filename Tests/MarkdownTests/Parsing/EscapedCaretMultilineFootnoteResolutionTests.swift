/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A cross-line escaped-caret `[\^…]` whose captured label matches a definition resolves as a footnote.
///
/// Ground truth is cmark-gfm (flag-ON). For `[\^abcdef` LF `xxxxx]` cmark's column-derived capture yields the
/// label `abc`; with `[^abc]: note` defined, cmark emits a FootnoteReference and keeps the definition. When the
/// capture doesn't match a definition (`[^abcdef]`, or `[\^ab` LF `x]` with `[^ab]`) both parsers already agree.
class EscapedCaretMultilineFootnoteResolutionTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        var options = ParseOptions(rawValue: UInt(0xd0 & 0b11011111))
        options.insert(.cmarkBugCompatibility)
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private static let resolved = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"abc\" index: 1\n└─ FootnoteDefinition label: \"abc\"\n   └─ Paragraph\n      └─ Text \"note\""

    func testCapturedLabelResolves() {
        XCTAssertEqual(Self.resolved, surface("[\\^abcdef\nxxxxx]\n\n[^abc]: note"))
    }

    func testShorterFirstLineResolves() {
        XCTAssertEqual(Self.resolved, surface("[\\^abc\nxxxxx]\n\n[^abc]: note"))
    }

    func testImageFormResolvesDroppingBang() {
        XCTAssertEqual(Self.resolved, surface("![\\^abcdef\nxxxxx]\n\n[^abc]: note"))
    }

    func testCaseFoldedCaptureResolves() {
        XCTAssertEqual(Self.resolved, surface("[\\^ABCdef\nxxxxx]\n\n[^abc]: note"))
    }

    func testCaptureAtCapResolves() {
        let label = String(repeating: "a", count: 1000)
        let expected = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"\(label)\" index: 1\n└─ FootnoteDefinition label: \"\(label)\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^\(label)bbb\n\(String(repeating: "x", count: 1002))]\n\n[^\(label)]: note"))
    }

    func testCaptureOverCapStaysLiteral() {
        let label = String(repeating: "a", count: 1001)
        let expected = "Document\n└─ Paragraph\n   └─ Text \"[^\(label)]\""
        XCTAssertEqual(expected, surface("[\\^\(label)bbb\n\(String(repeating: "x", count: 1003))]\n\n[^\(label)]: note"))
    }

    func testCaptureContainingNULResolves() {
        let expected = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"a\u{FFFD}b\" index: 1\n└─ FootnoteDefinition label: \"a\u{FFFD}b\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^a\u{0}bcdef\nxxxxxxx]\n\n[^a\u{0}b]: note"))
    }

    func testTwoReferencesShareOneDefinition() {
        let expected = "Document\n├─ Paragraph\n│  ├─ FootnoteReference label: \"abc\" index: 1\n│  ├─ SoftBreak\n│  └─ FootnoteReference label: \"abc\" index: 1\n└─ FootnoteDefinition label: \"abc\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^abcdef\nxxxxx]\n[\\^abcdef\nxxxxx]\n\n[^abc]: note"))
    }

    func testLaterPlainReferenceSharesDefinition() {
        let expected = "Document\n├─ Paragraph\n│  ├─ FootnoteReference label: \"abc\" index: 1\n│  ├─ Text \" \"\n│  └─ FootnoteReference label: \"abc\" index: 1\n└─ FootnoteDefinition label: \"abc\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^abcdef\nxxxxx] [^abc]\n\n[^abc]: note"))
    }

    func testNumberedInDocumentOrderAfterEarlierPlainReference() {
        let expected = "Document\n├─ Paragraph\n│  ├─ FootnoteReference label: \"zzz\" index: 1\n│  ├─ SoftBreak\n│  └─ FootnoteReference label: \"abc\" index: 2\n├─ FootnoteDefinition label: \"zzz\"\n│  └─ Paragraph\n│     └─ Text \"z\"\n└─ FootnoteDefinition label: \"abc\"\n   └─ Paragraph\n      └─ Text \"a\""
        XCTAssertEqual(expected, surface("[^zzz]\n[\\^abcdef\nxxxxx]\n\n[^abc]: a\n\n[^zzz]: z"))
    }

    func testCaptureEndingInSoftBreakResolves() {
        let expected = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"ab\" index: 1\n└─ FootnoteDefinition label: \"ab\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^ab\nxxxxx]\n\n[^ab]: note"))
    }

    func testCaptureCutMidScalarResolves() {
        let expected = "Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"ab\u{FFFD}\" index: 1\n└─ FootnoteDefinition label: \"ab\u{FFFD}\"\n   └─ Paragraph\n      └─ Text \"note\""
        XCTAssertEqual(expected, surface("[\\^ab\u{E9}\nxxxxx]\n\n[^ab\u{FFFD}]: note"))
    }

    /// A plain-caret cross-line capture whose length underflows stays literal (and doesn't trap).
    func testUnderflowedPlainCaretCaptureStaysLiteral() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^]\"", surface("[^a\nx]\n\n[^a]: note"))
    }
}
