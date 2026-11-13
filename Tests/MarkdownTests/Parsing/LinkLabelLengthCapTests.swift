/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A link label holds at most 1000 bytes of its block's content inside its brackets, counting a NUL as the three bytes
/// of the U+FFFD that replaces it (Insecure characters); a longer bracketed span is not a link label, in a link
/// reference definition or in any form of reference link.
class LinkLabelLengthCapTests: XCTestCase {
    private func linkCount(_ markdown: String) -> Int {
        Document(parsing: markdown, options: []).debugDescription(options: [])
            .components(separatedBy: "Link destination:").count - 1
    }

    /// A use whose label content is `length` characters: `x`, then spaces, then `y`.
    private func label(_ length: Int) -> String {
        "[x" + String(repeating: " ", count: length - 2) + "y]"
    }

    func testShortcutCollapsedAndFullOf999CharactersResolve() {
        for (use, suffix) in [("", ""), ("", "[]"), ("[t]", "")] {
            XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + use + label(999) + suffix), "\(use)|\(suffix)")
        }
    }

    func testDefinitionOf999CharactersRegisters() {
        XCTAssertEqual(1, linkCount(label(999) + ": /u\n\n[x y]"))
    }

    /// 500 `é` (1000 bytes) is a link label; 501 is not.
    func testCountsBytesNotCharacters() {
        let e500 = "[" + String(repeating: "\u{E9}", count: 500) + "]"
        let e501 = "[" + String(repeating: "\u{E9}", count: 501) + "]"
        XCTAssertEqual(1, linkCount(e500 + ": /u\n\n" + e500))
        XCTAssertEqual(0, linkCount(e501 + ": /u\n\n" + e501))
        let definition = "[\u{20AC} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 996) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 997) + "y]"))
    }

    /// A NUL is three bytes, the U+FFFD that replaces it (Insecure characters).
    func testCountsNULAsThreeBytes() {
        let definition = "[x \u{0} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 994) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 995) + "y]"))
    }

    // MARK: Full trees

    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    private func literalParagraph(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(text)\""
    }

    private func resolvedLink(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"\(text)\""
    }

    func testShortcutOf1000BytesResolves() {
        XCTAssertEqual(resolvedLink("x" + String(repeating: " ", count: 998) + "y"), tree("[x y]: /u\n\n" + label(1000)))
    }

    func testShortcutOf1001BytesStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1001)), tree("[x y]: /u\n\n" + label(1001)))
    }

    func testCollapsedOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1001) + "[]"), tree("[x y]: /u\n\n" + label(1001) + "[]"))
        XCTAssertEqual(literalParagraph(label(1002) + "[]"), tree("[x y]: /u\n\n" + label(1002) + "[]"))
    }

    func testFullOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("[t]" + label(1001)), tree("[x y]: /u\n\n[t]" + label(1001)))
        XCTAssertEqual(literalParagraph("[t]" + label(1002)), tree("[x y]: /u\n\n[t]" + label(1002)))
    }

    func testMultibyteShortcutCountsBytes() {
        let definition = "[\u{20AC} y]: /u\n\n"
        let fits = "\u{20AC}" + String(repeating: " ", count: 996) + "y"
        let over = "\u{20AC}" + String(repeating: " ", count: 997) + "y"
        XCTAssertEqual(resolvedLink(fits), tree(definition + "[" + fits + "]"))
        XCTAssertEqual(literalParagraph("[" + over + "]"), tree(definition + "[" + over + "]"))
    }

    func testNULShortcutCountsThreeBytes() {
        let definition = "[x \u{0} y]: /u\n\n"
        let fits = String(repeating: " ", count: 994)
        let over = String(repeating: " ", count: 995)
        XCTAssertEqual(resolvedLink("x \u{FFFD}" + fits + "y"), tree(definition + "[x \u{0}" + fits + "y]"))
        XCTAssertEqual(literalParagraph("[x \u{FFFD}" + over + "y]"), tree(definition + "[x \u{0}" + over + "y]"))
    }

    func testImageShortcutOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("!" + label(1001)), tree("[x y]: /u\n\n!" + label(1001)))
        XCTAssertEqual(literalParagraph("!" + label(1002)), tree("[x y]: /u\n\n!" + label(1002)))
    }

    /// Counting its line ending as one byte, and no block quote marker, the label fits with 997 spaces before the line
    /// ending and is over the limit with 998. The spaces before the line ending make a hard line break.
    func testMultilineShortcutAtAndOverCap() {
        let spaces = { String(repeating: " ", count: $0) }
        let quotedLink = "Document\n└─ BlockQuote\n   └─ Paragraph\n      └─ Link destination: \"/u\"\n         ├─ Text \"x\"\n         ├─ LineBreak\n         └─ Text \"y\""
        let plainLink = "Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      ├─ Text \"x\"\n      ├─ LineBreak\n      └─ Text \"y\""
        let quoted = "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"[x\"\n      ├─ LineBreak\n      └─ Text \"y]\""
        let plain = "Document\n└─ Paragraph\n   ├─ Text \"[x\"\n   ├─ LineBreak\n   └─ Text \"y]\""
        XCTAssertEqual(quotedLink, tree("[x y]: /u\n\n> [x" + spaces(997) + "\n>    y]"))
        XCTAssertEqual(quoted, tree("[x y]: /u\n\n> [x" + spaces(998) + "\n>    y]"))
        XCTAssertEqual(plainLink, tree("[x y]: /u\r\n\r\n[x" + spaces(997) + "\r\ny]"))
        XCTAssertEqual(plain, tree("[x y]: /u\r\n\r\n[x" + spaces(998) + "\r\ny]"))
    }

    /// A blank `[ ]` is not a link label, so the label before it is a shortcut reference held to the same limit.
    func testBlankFullLabelFallbackOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1001) + "[ ]"), tree("[x y]: /u\n\n" + label(1001) + "[ ]"))
        XCTAssertEqual(literalParagraph(label(1002) + "[ ]"), tree("[x y]: /u\n\n" + label(1002) + "[ ]"))
    }

    func testDefinitionOverCapDoesNotRegister() {
        for length in [1001, 1002] {
            XCTAssertEqual(
                "Document\n├─ Paragraph\n│  └─ Text \"\(label(length)): /u\"\n└─ Paragraph\n   └─ Text \"[x y]\"",
                tree(label(length) + ": /u\n\n[x y]")
            )
        }
    }

    func testMultibyteDefinitionAndUseCountBytes() {
        let fits = String(repeating: "\u{E9}", count: 500)
        let over = String(repeating: "\u{E9}", count: 501)
        XCTAssertEqual(resolvedLink(fits), tree("[" + fits + "]: /u\n\n[" + fits + "]"))
        XCTAssertEqual(
            "Document\n├─ Paragraph\n│  └─ Text \"[\(over)]: /u\"\n└─ Paragraph\n   └─ Text \"[\(over)]\"",
            tree("[" + over + "]: /u\n\n[" + over + "]")
        )
    }
}
