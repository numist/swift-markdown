/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Character references inside an autolink decode in its destination and text (Entity and numeric character
/// references).
class AutolinkEntityDecodingTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    private static func autolink(_ url: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"\(url)\"\n      └─ Text \"\(url)\""
    }

    func testUnknownNamedEntityStaysLiteral() {
        XCTAssertEqual(Self.autolink("http://a&bogus;b"), tree("<http://a&bogus;b>"))
    }

    func testDigitlessHexReferenceStaysLiteral() {
        XCTAssertEqual(Self.autolink("http://a&#x;b"), tree("<http://a&#x;b>"))
    }

    func testReferenceAboveUnicodeRangeBecomesReplacementCharacter() {
        XCTAssertEqual(Self.autolink("http://a\u{fffd}"), tree("<http://a&#1114112;>"))
        XCTAssertEqual(Self.autolink("http://a\u{fffd}"), tree("<http://a&#xFFFFFF;>"))
    }

    func testSurrogateReferenceBecomesReplacementCharacter() {
        XCTAssertEqual(Self.autolink("http://a\u{fffd}b"), tree("<http://a&#xD800;b>"))
    }

    func testMultiByteNamedEntityDecodes() {
        XCTAssertEqual(Self.autolink("xy:&z\u{e9}"), tree("<xy:&amp;z&eacute;>"))
    }

    func testBackslashStaysLiteralWhileReferenceDecodes() {
        XCTAssertEqual(Self.autolink("http://a\\&b"), tree("<http://a\\&amp;b>"))
    }

    func testReferenceDecodesOnAContinuationLine() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Link destination: \"http://a&b\"\n      └─ Text \"http://a&b\"",
            tree("x\n<http://a&amp;b>")
        )
    }

    func testEightDigitReferenceStaysLiteral() {
        // A decimal numeric character reference has at most 7 digits.
        XCTAssertEqual(Self.autolink("http://a&#12345678;b"), tree("<http://a&#12345678;b>"))
    }

    func testEmailAutolinkWithAmpersandKeepsItLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"mailto:a&b@c.d\"\n      └─ Text \"a&b@c.d\"",
            tree("<a&b@c.d>")
        )
    }

    func testReferenceDecodesInEscapedPipeCellQuotedHeadingAndNULParagraph() {
        XCTAssertEqual(
            """
            Document
            └─ Table alignments: |-|
               ├─ Head
               │  └─ Cell
               │     └─ Text "a"
               └─ Body
                  └─ Row
                     └─ Cell
                        ├─ Link destination: "http://a&b"
                        │  └─ Text "http://a&b"
                        └─ Text " | x"
            """,
            tree("| a |\n|---|\n| <http://a&amp;b> \\| x |")
        )
        XCTAssertEqual(
            """
            Document
            └─ BlockQuote
               └─ Heading level: 1
                  ├─ Text "a"
                  ├─ SoftBreak
                  └─ Link destination: "http://a&b"
                     └─ Text "http://a&b"
            """,
            tree("> a\n> <http://a&amp;b>\n> ===")
        )
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"a\u{fffd}\"\n   └─ Link destination: \"http://a&b\"\n      └─ Text \"http://a&b\"",
            tree("a\u{0}<http://a&amp;b>")
        )
    }

    func testNamedAndDecimalReferencesDecode() {
        XCTAssertEqual(Self.autolink("http://a&b"), tree("<http://a&amp;b>"))
        XCTAssertEqual(Self.autolink("op:\u{fffd}"), tree("<op:&#0;>"))
        XCTAssertEqual(Self.autolink("http://aAb"), tree("<http://a&#65;b>"))
    }

    func testEmailFormCannotHoldAReference() {
        // `;` is not allowed in an email address (Autolinks), so no autolink forms and the `&amp;` decodes as
        // text.
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"<a&b@c.d>\"",
            tree("<a&amp;b@c.d>")
        )
    }
}
