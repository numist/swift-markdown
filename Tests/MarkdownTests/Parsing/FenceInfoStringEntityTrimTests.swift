/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// The info string is trimmed of leading and trailing whitespace before its character references are decoded
// (Fenced code blocks), so whitespace that a reference decodes to is kept.
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
        XCTAssertEqual("\t", language("```&#9;"))
        XCTAssertEqual("\tx", language("```&#9;x"))
        XCTAssertEqual("x ", language("```x&#32;"))
        XCTAssertEqual("\t", language("~~~&#9;"))
        XCTAssertEqual(" ", language("```&#32;"))
        XCTAssertEqual("\n", language("```&#10;"))
        XCTAssertEqual(" x", language("``` &#32;x"))
        XCTAssertEqual("\t x", language("```&#9; x"))
        XCTAssertEqual("x\t", language("```x&#9;"))
        XCTAssertEqual(" x", language("```&#x20;x"))
        XCTAssertEqual("\t", language("```&#x9;"))
        XCTAssertEqual("\t \nx\r\t", language("```&#9;&#32;&#10;x&#13;&#9;"))
        XCTAssertEqual(" +x", language("```&#32;\\+x"))
    }

    func testBackslashEscapesReferenceAmpersand() {
        XCTAssertEqual("x&#32;", language("```x\\&#32;"))
        XCTAssertEqual("&#9;x", language("```\\&#9;x"))
        XCTAssertEqual("&#3;", language("```\\&#3;"))
        XCTAssertEqual("&amp;", language("```\\&amp;"))
    }
}
