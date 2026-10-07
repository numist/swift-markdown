/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Sibling probes for `AutolinkEntityDecodingTests`: the decoder's edge cases inside a `<scheme:…>`
/// autolink, the spec-correct deliverable (flag-OFF), and the GFM extended autolink (which cmark does
/// NOT decode). Expected trees derived from swift-cmark `src/houdini_html_u.c` (`houdini_unescape_ent`)
/// and `extensions/autolink.c`.
class AutolinkEntityDecodingEdgeTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    private static func autolink(_ url: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"\(url)\"\n      └─ Text \"\(url)\""
    }

    func testUnknownNamedEntityStaysLiteral() {
        XCTAssertEqual(Self.autolink("http://a&bogus;b"), surface("<http://a&bogus;b>"))
    }

    func testDigitlessHexReferenceStaysLiteral() {
        XCTAssertEqual(Self.autolink("http://a&#x;b"), surface("<http://a&#x;b>"))
    }

    func testReferenceAboveUnicodeRangeBecomesReplacementCharacter() {
        XCTAssertEqual(Self.autolink("http://a\u{fffd}"), surface("<http://a&#1114112;>"))
        XCTAssertEqual(Self.autolink("http://a\u{fffd}"), surface("<http://a&#xFFFFFF;>"))
    }

    func testSurrogateReferenceBecomesReplacementCharacter() {
        XCTAssertEqual(Self.autolink("http://a\u{fffd}b"), surface("<http://a&#xD800;b>"))
    }

    func testMultiByteNamedEntityDecodes() {
        XCTAssertEqual(Self.autolink("xy:&z\u{e9}"), surface("<xy:&amp;z&eacute;>"))
    }

    func testBackslashStaysLiteralWhileReferenceDecodes() {
        XCTAssertEqual(Self.autolink("http://a\\&b"), surface("<http://a\\&amp;b>"))
    }

    func testReferenceDecodesOnAContinuationLine() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"x\"\n   ├─ SoftBreak\n   └─ Link destination: \"http://a&b\"\n      └─ Text \"http://a&b\"",
            surface("x\n<http://a&amp;b>")
        )
    }

    func testEightDigitReferenceFollowsTheFlag() {
        // CommonMark §6.2 caps decimal at 7.
        XCTAssertEqual(Self.autolink("http://a&#12345678;b"), surface("<http://a&#12345678;b>"))
    }

    func testEmailAutolinkWithAmpersandKeepsItLiteral() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Link destination: \"mailto:a&b@c.d\"\n      └─ Text \"a&b@c.d\"",
            surface("<a&b@c.d>")
        )
    }

    /// Autolinks inside content the parser materializes into the arena: a `\\|`-unescaped table cell, a
    /// flattened setext heading inside a block quote, and a paragraph holding a NUL.
    func testReferenceDecodesInArenaBackedContent() {
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
            surface("| a |\n|---|\n| <http://a&amp;b> \\| x |")
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
            surface("> a\n> <http://a&amp;b>\n> ===")
        )
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"a\u{fffd}\"\n   └─ Link destination: \"http://a&b\"\n      └─ Text \"http://a&b\"",
            surface("a\u{0}<http://a&amp;b>")
        )
    }

    func testDeliverableDecodesToo() {
        XCTAssertEqual(Self.autolink("http://a&b"), surface("<http://a&amp;b>"))
        XCTAssertEqual(Self.autolink("op:\u{fffd}"), surface("<op:&#0;>"))
        XCTAssertEqual(Self.autolink("http://aAb"), surface("<http://a&#65;b>"))
    }

    func testEmailFormCannotHoldAReference() {
        XCTAssertEqual(
            // `;` is outside the email local-part class, so no autolink forms; the `&amp;` decodes as ordinary
            // inline text and `cmark_parser_finish` (`blocks.c`) consolidates the adjacent text nodes.
            "Document\n└─ Paragraph\n   └─ Text \"<a&b@c.d>\"",
            surface("<a&amp;b@c.d>")
        )
    }
}
