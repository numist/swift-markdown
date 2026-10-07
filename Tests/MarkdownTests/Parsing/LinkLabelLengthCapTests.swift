/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// A link label holds at most 999 characters inside its brackets (Links); a longer bracketed span is not a
/// link label, in a link reference definition or in any form of reference link.
class LinkLabelLengthCapTests: XCTestCase {
    private func linkCount(_ markdown: String) -> Int {
        Document(parsing: markdown, options: []).debugDescription(options: [])
            .components(separatedBy: "Link destination:").count - 1
    }

    /// A use whose label content is `length` bytes: `x`, then spaces, then `y`.
    private func label(_ length: Int) -> String {
        "[x" + String(repeating: " ", count: length - 2) + "y]"
    }

    func testShortcutCollapsedAndFullCapAt999Characters() {
        for (use, suffix) in [("", ""), ("", "[]"), ("[t]", "")] {
            XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + use + label(999) + suffix), "\(use)|\(suffix)")
            XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + use + label(1000) + suffix), "\(use)|\(suffix)")
        }
    }

    func testDefinitionCapAt999Characters() {
        XCTAssertEqual(1, linkCount(label(999) + ": /u\n\n[x y]"))
        XCTAssertEqual(0, linkCount(label(1000) + ": /u\n\n[x y]"))
    }

    /// 999 `é` (1998 bytes) is a link label; 1000 is not.
    func testCountsCharactersNotBytes() {
        let e999 = "[" + String(repeating: "\u{E9}", count: 999) + "]"
        let e1000 = "[" + String(repeating: "\u{E9}", count: 1000) + "]"
        XCTAssertEqual(1, linkCount(e999 + ": /u\n\n" + e999))
        XCTAssertEqual(0, linkCount(e1000 + ": /u\n\n" + e1000))
        let definition = "[\u{20AC} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 997) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 998) + "y]"))
    }

    /// A NUL is one character, the U+FFFD that replaces it (Insecure characters).
    func testCountsNULAsOneCharacter() {
        let definition = "[x \u{0} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 995) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 996) + "y]"))
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

    func testShortcutOf1000CharactersStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000)), tree("[x y]: /u\n\n" + label(1000)))
    }

    func testShortcutOf1001CharactersStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1001)), tree("[x y]: /u\n\n" + label(1001)))
    }

    func testCollapsedOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000) + "[]"), tree("[x y]: /u\n\n" + label(1000) + "[]"))
        XCTAssertEqual(literalParagraph(label(1001) + "[]"), tree("[x y]: /u\n\n" + label(1001) + "[]"))
    }

    func testFullOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("[t]" + label(1000)), tree("[x y]: /u\n\n[t]" + label(1000)))
        XCTAssertEqual(literalParagraph("[t]" + label(1001)), tree("[x y]: /u\n\n[t]" + label(1001)))
    }

    func testMultibyteShortcutCountsCharacters() {
        let definition = "[\u{20AC} y]: /u\n\n"
        for spaces in [996, 997] {
            let content = "\u{20AC}" + String(repeating: " ", count: spaces) + "y"
            XCTAssertEqual(resolvedLink(content), tree(definition + "[" + content + "]"))
        }
    }

    func testNULShortcutCountsOneCharacter() {
        let definition = "[x \u{0} y]: /u\n\n"
        for spaces in [994, 995] {
            let padding = String(repeating: " ", count: spaces)
            XCTAssertEqual(resolvedLink("x \u{FFFD}" + padding + "y"), tree(definition + "[x \u{0}" + padding + "y]"))
        }
    }

    func testImageShortcutOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("!" + label(1000)), tree("[x y]: /u\n\n!" + label(1000)))
        XCTAssertEqual(literalParagraph("!" + label(1001)), tree("[x y]: /u\n\n!" + label(1001)))
    }

    /// Counting its line ending, each label exceeds 999 characters. The spaces before the line ending make a
    /// hard line break.
    func testMultilineShortcutOverCapStaysLiteral() {
        let spaces = { String(repeating: " ", count: $0) }
        let quoted = "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"[x\"\n      ├─ LineBreak\n      └─ Text \"y]\""
        let plain = "Document\n└─ Paragraph\n   ├─ Text \"[x\"\n   ├─ LineBreak\n   └─ Text \"y]\""
        XCTAssertEqual(quoted, tree("[x y]: /u\n\n> [x" + spaces(997) + "\n>    y]"))
        XCTAssertEqual(quoted, tree("[x y]: /u\n\n> [x" + spaces(998) + "\n>    y]"))
        XCTAssertEqual(plain, tree("[x y]: /u\r\n\r\n[x" + spaces(997) + "\r\ny]"))
        XCTAssertEqual(plain, tree("[x y]: /u\r\n\r\n[x" + spaces(998) + "\r\ny]"))
    }

    /// A blank `[ ]` is not a link label, so the label before it is a shortcut reference held to the same limit.
    func testBlankFullLabelFallbackOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000) + "[ ]"), tree("[x y]: /u\n\n" + label(1000) + "[ ]"))
        XCTAssertEqual(literalParagraph(label(1001) + "[ ]"), tree("[x y]: /u\n\n" + label(1001) + "[ ]"))
    }

    func testDefinitionOverCapDoesNotRegister() {
        for length in [1000, 1001] {
            XCTAssertEqual(
                "Document\n├─ Paragraph\n│  └─ Text \"\(label(length)): /u\"\n└─ Paragraph\n   └─ Text \"[x y]\"",
                tree(label(length) + ": /u\n\n[x y]")
            )
        }
    }

    func testMultibyteDefinitionAndUseCountCharacters() {
        for count in [500, 501] {
            let content = String(repeating: "\u{E9}", count: count)
            XCTAssertEqual(resolvedLink(content), tree("[" + content + "]: /u\n\n[" + content + "]"))
        }
    }
}
