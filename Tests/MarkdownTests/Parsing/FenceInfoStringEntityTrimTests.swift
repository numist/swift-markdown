/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class FenceInfoStringEntityTrimTests: XCTestCase {
    private func language(_ markdown: String) -> String? {
        let document = Document(parsing: markdown, options: [])
        return (document.child(at: 0) as? CodeBlock)?.language
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

    /// Flag-off follows the spec: the info string is trimmed before its references are decoded.
    func testFlagOffKeepsDecodedEdgeWhitespace() {
        func languageFlagOff(_ markdown: String) -> String? {
            (Document(parsing: markdown, options: []).child(at: 0) as? CodeBlock)?.language
        }
        XCTAssertEqual("\t", languageFlagOff("```&#9;"))
        XCTAssertEqual("\tx", languageFlagOff("```&#9;x"))
        XCTAssertEqual("x ", languageFlagOff("```x&#32;"))
        XCTAssertEqual("\t", languageFlagOff("~~~&#9;"))
        XCTAssertEqual(" ", languageFlagOff("```&#32;"))
        XCTAssertEqual("\n", languageFlagOff("```&#10;"))
        XCTAssertEqual(" x", languageFlagOff("``` &#32;x"))
        XCTAssertEqual("\t x", languageFlagOff("```&#9; x"))
        XCTAssertEqual("x\t", languageFlagOff("```x&#9;"))
        XCTAssertEqual(" x", languageFlagOff("```&#x20;x"))
        XCTAssertEqual("\t", languageFlagOff("```&#x9;"))
        XCTAssertEqual("\t \nx\r\t", languageFlagOff("```&#9;&#32;&#10;x&#13;&#9;"))
        XCTAssertEqual(" +x", languageFlagOff("```&#32;\\+x"))
    }

    /// Flag-off the info string is processed in one left-to-right pass, so a backslash escapes the `&` of a
    /// following reference and the reference stays literal.
    func testFlagOffBackslashEscapesReferenceAmpersand() {
        XCTAssertEqual("x&#32;", language("```x\\&#32;"))
        XCTAssertEqual("&#9;x", language("```\\&#9;x"))
    }
}
