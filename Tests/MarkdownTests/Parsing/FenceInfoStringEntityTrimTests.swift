/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A fenced code block's info string is trimmed after its character references are decoded.
///
/// Ground truth is cmark-gfm (flag-ON). cmark unescapes the info string and then trims it, so whitespace
/// produced by a reference (`&#9;`, `&#32;`, `&#10;`) at either end disappears: ```` ```&#9; ```` has no
/// language and ```` ```&#9;x ```` has language `x`. Interior decoded whitespace stays (`x&#9;y`).
class FenceInfoStringEntityTrimTests: XCTestCase {
    private func language(_ markdown: String) -> String? {
        let document = Document(parsing: markdown, options: [.cmarkBugCompatibility])
        return (document.child(at: 0) as? CodeBlock)?.language
    }

    func testDecodedTabOnlyInfoHasNoLanguage() {
        XCTAssertNil(language("```&#9;"))
        XCTAssertNil(language("~~~&#9;"))
    }

    func testDecodedSpaceAndNewlineOnlyInfoHasNoLanguage() {
        XCTAssertNil(language("```&#32;"))
        XCTAssertNil(language("```&#10;"))
    }

    func testLeadingDecodedWhitespaceTrimmed() {
        XCTAssertEqual("x", language("```&#9;x"))
        XCTAssertEqual("x", language("``` &#32;x"))
        XCTAssertEqual("x", language("```&#9; x"))
    }

    func testTrailingDecodedWhitespaceTrimmed() {
        XCTAssertEqual("x", language("```x&#9;"))
    }

    func testHexReferencesTrimmed() {
        XCTAssertEqual("x", language("```&#x20;x"))
        XCTAssertNil(language("```&#x9;"))
    }

    func testMultipleReferencesTrimmed() {
        XCTAssertEqual("x", language("```&#9;&#32;&#10;x&#13;&#9;"))
    }

    /// cmark's trim set is `cmark_isspace` (space, tab, LF, CR), so a decoded no-break space or vertical tab stays.
    func testNonCmarkSpaceReferencesKept() {
        XCTAssertEqual("\u{A0}x", language("```&nbsp;x"))
        XCTAssertEqual("x\u{A0}", language("```x&nbsp;"))
        XCTAssertEqual("\u{0B}x", language("```&#11;x"))
    }

    func testInteriorDecodedWhitespaceKept() {
        XCTAssertEqual("x\ty", language("```x&#9;y"))
    }

    /// cmark trims between decoding references and stripping backslash escapes.
    func testTrimRunsBetweenDecodingAndBackslashUnescape() {
        XCTAssertEqual("+x", language("```&#32;\\+x"))
        XCTAssertEqual("x\\", language("```x\\&#32;"))
        XCTAssertEqual("\\\tx", language("```\\&#9;x"))
    }

    /// Flag-off follows the spec: the info string is trimmed before its references are decoded.
    func testFlagOffKeepsDecodedEdgeWhitespace() {
        func languageFlagOff(_ markdown: String) -> String? {
            (Document(parsing: markdown, options: []).child(at: 0) as? CodeBlock)?.language
        }
        XCTAssertEqual("\t", languageFlagOff("```&#9;"))
        XCTAssertEqual("\tx", languageFlagOff("```&#9;x"))
        XCTAssertEqual("x ", languageFlagOff("```x&#32;"))
    }
}
