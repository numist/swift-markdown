/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A fenced code block's info string is trimmed of leading and trailing whitespace (Fenced code blocks)
/// before its character references are decoded, so characters that references decode to are kept.
class FenceInfoStringEntityTrimTests: XCTestCase {
    private func language(_ markdown: String) -> String? {
        let document = Document(parsing: markdown, options: [])
        return (document.child(at: 0) as? CodeBlock)?.language
    }

    func testDecodedNoBreakSpaceAndLineTabulationKept() {
        XCTAssertEqual("\u{A0}x", language("```&nbsp;x"))
        XCTAssertEqual("x\u{A0}", language("```x&nbsp;"))
        XCTAssertEqual("\u{0B}x", language("```&#11;x"))
    }

    func testInteriorDecodedWhitespaceKept() {
        XCTAssertEqual("x\ty", language("```x&#9;y"))
    }

    func testDecodedEdgeWhitespaceKept() {
        func infoString(_ markdown: String) -> String? {
            (Document(parsing: markdown, options: []).child(at: 0) as? CodeBlock)?.language
        }
        XCTAssertEqual("\t", infoString("```&#9;"))
        XCTAssertEqual("\tx", infoString("```&#9;x"))
        XCTAssertEqual("x ", infoString("```x&#32;"))
        XCTAssertEqual("\t", infoString("~~~&#9;"))
        XCTAssertEqual(" ", infoString("```&#32;"))
        XCTAssertEqual("\n", infoString("```&#10;"))
        XCTAssertEqual(" x", infoString("``` &#32;x"))
        XCTAssertEqual("\t x", infoString("```&#9; x"))
        XCTAssertEqual("x\t", infoString("```x&#9;"))
        XCTAssertEqual(" x", infoString("```&#x20;x"))
        XCTAssertEqual("\t", infoString("```&#x9;"))
        XCTAssertEqual("\t \nx\r\t", infoString("```&#9;&#32;&#10;x&#13;&#9;"))
        XCTAssertEqual(" +x", infoString("```&#32;\\+x"))
    }

    /// A backslash escapes the `&` that follows it (Backslash escapes), so the reference is literal text.
    func testBackslashEscapesReferenceAmpersand() {
        XCTAssertEqual("x&#32;", language("```x\\&#32;"))
        XCTAssertEqual("&#9;x", language("```\\&#9;x"))
    }
}
