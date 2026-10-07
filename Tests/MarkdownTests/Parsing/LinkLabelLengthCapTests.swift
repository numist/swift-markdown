/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class LinkLabelLengthCapTests: XCTestCase {
    private func linkCount(_ markdown: String) -> Int {
        Document(parsing: markdown, options: []).debugDescription(options: [])
            .components(separatedBy: "Link destination:").count - 1
    }

    /// A use whose label content is `length` bytes: `x`, then spaces, then `y`.
    private func label(_ length: Int) -> String {
        "[x" + String(repeating: " ", count: length - 2) + "y]"
    }

    // MARK: Spec (flag-off): at most 999 characters inside the brackets

    func testSpecShortcutCollapsedAndFullCapAt999Characters() {
        for (use, suffix) in [("", ""), ("", "[]"), ("[t]", "")] {
            XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + use + label(999) + suffix), "\(use)|\(suffix)")
            XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + use + label(1000) + suffix), "\(use)|\(suffix)")
        }
    }

    func testSpecDefinitionCapAt999Characters() {
        XCTAssertEqual(1, linkCount(label(999) + ": /u\n\n[x y]"))
        XCTAssertEqual(0, linkCount(label(1000) + ": /u\n\n[x y]"))
    }

    /// The spec counts characters: 999 `é` (1998 bytes) is a label, 1000 is not.
    func testSpecCountsCharactersNotBytes() {
        let e999 = "[" + String(repeating: "\u{E9}", count: 999) + "]"
        let e1000 = "[" + String(repeating: "\u{E9}", count: 1000) + "]"
        XCTAssertEqual(1, linkCount(e999 + ": /u\n\n" + e999))
        XCTAssertEqual(0, linkCount(e1000 + ": /u\n\n" + e1000))
        let definition = "[\u{20AC} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 997) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 998) + "y]"))
    }

    /// A NUL is one character (the U+FFFD it becomes), not three.
    func testSpecCountsNULAsOneCharacter() {
        let definition = "[x \u{0} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 995) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 996) + "y]"))
    }

    // MARK: Flag-off twins of the cmark cases above

    private func shippedSurface(_ markdown: String) -> String {
        Document(parsing: markdown, options: []).debugDescription(options: [])
    }

    private func literalParagraph(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(text)\""
    }

    private func resolvedLink(_ text: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"\(text)\""
    }

    /// Flag-off (shipped): a 1000-character label is over the spec's 999, so it stays literal where
    /// cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffShortcutAtCmarkCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000)), shippedSurface("[x y]: /u\n\n" + label(1000)))
    }

    func testFlagOffShortcutOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1001)), shippedSurface("[x y]: /u\n\n" + label(1001)))
    }

    /// Flag-off (shipped): a 1000-character collapsed label is over the spec's 999, so it stays literal
    /// where cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffCollapsedOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000) + "[]"), shippedSurface("[x y]: /u\n\n" + label(1000) + "[]"))
        XCTAssertEqual(literalParagraph(label(1001) + "[]"), shippedSurface("[x y]: /u\n\n" + label(1001) + "[]"))
    }

    /// Flag-off (shipped): a 1000-character full label is over the spec's 999, so it stays literal where
    /// cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffFullOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("[t]" + label(1000)), shippedSurface("[x y]: /u\n\n[t]" + label(1000)))
        XCTAssertEqual(literalParagraph("[t]" + label(1001)), shippedSurface("[x y]: /u\n\n[t]" + label(1001)))
    }

    /// Flag-off (shipped): the spec counts the 3-byte `€` as one character, so a 999-character label
    /// resolves where cmark-gfm's byte count leaves it literal.
    func testFlagOffMultibyteShortcutCountsCharacters() {
        let definition = "[\u{20AC} y]: /u\n\n"
        for spaces in [996, 997] {
            let content = "\u{20AC}" + String(repeating: " ", count: spaces) + "y"
            XCTAssertEqual(resolvedLink(content), shippedSurface(definition + "[" + content + "]"))
        }
    }

    /// Flag-off (shipped): a NUL is one character (the U+FFFD it becomes), so a 999-character label
    /// resolves where cmark-gfm counts the replacement's 3 bytes and leaves it literal.
    func testFlagOffNULShortcutCountsOneCharacter() {
        let definition = "[x \u{0} y]: /u\n\n"
        for spaces in [994, 995] {
            let padding = String(repeating: " ", count: spaces)
            XCTAssertEqual(resolvedLink("x \u{FFFD}" + padding + "y"), shippedSurface(definition + "[x \u{0}" + padding + "y]"))
        }
    }

    /// Flag-off (shipped): a 1000-character image label is over the spec's 999, so it stays literal where
    /// cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffImageShortcutOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph("!" + label(1000)), shippedSurface("[x y]: /u\n\n!" + label(1000)))
        XCTAssertEqual(literalParagraph("!" + label(1001)), shippedSurface("[x y]: /u\n\n!" + label(1001)))
    }

    /// Flag-off (shipped): with its line ending the label holds 1000 characters, over the spec's 999, so it
    /// stays literal where cmark-gfm's 1000-byte cap resolves it; the trailing spaces make a hard line break.
    func testFlagOffMultilineShortcutOverCapStaysLiteral() {
        let spaces = { String(repeating: " ", count: $0) }
        let quoted = "Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"[x\"\n      ├─ LineBreak\n      └─ Text \"y]\""
        let plain = "Document\n└─ Paragraph\n   ├─ Text \"[x\"\n   ├─ LineBreak\n   └─ Text \"y]\""
        XCTAssertEqual(quoted, shippedSurface("[x y]: /u\n\n> [x" + spaces(997) + "\n>    y]"))
        XCTAssertEqual(quoted, shippedSurface("[x y]: /u\n\n> [x" + spaces(998) + "\n>    y]"))
        XCTAssertEqual(plain, shippedSurface("[x y]: /u\r\n\r\n[x" + spaces(997) + "\r\ny]"))
        XCTAssertEqual(plain, shippedSurface("[x y]: /u\r\n\r\n[x" + spaces(998) + "\r\ny]"))
    }

    /// Flag-off (shipped): the shortcut label before a blank `[ ]` is capped at 999 characters, so a
    /// 1000-character one stays literal where cmark-gfm's 1000-byte cap resolves it.
    func testFlagOffBlankFullLabelFallbackOverCapStaysLiteral() {
        XCTAssertEqual(literalParagraph(label(1000) + "[ ]"), shippedSurface("[x y]: /u\n\n" + label(1000) + "[ ]"))
        XCTAssertEqual(literalParagraph(label(1001) + "[ ]"), shippedSurface("[x y]: /u\n\n" + label(1001) + "[ ]"))
    }

    /// Flag-off (shipped): a definition with a 1000-character label is over the spec's 999, so it does not
    /// register where cmark-gfm's 1000-byte cap accepts it.
    func testFlagOffDefinitionOverCapDoesNotRegister() {
        for length in [1000, 1001] {
            XCTAssertEqual(
                "Document\n├─ Paragraph\n│  └─ Text \"\(label(length)): /u\"\n└─ Paragraph\n   └─ Text \"[x y]\"",
                shippedSurface(label(length) + ": /u\n\n[x y]")
            )
        }
    }

    /// Flag-off (shipped): 501 `é` are 501 characters, within the spec's 999, so they define and resolve
    /// where cmark-gfm's byte count of 1002 rejects them.
    func testFlagOffMultibyteDefinitionAndUseCountCharacters() {
        for count in [500, 501] {
            let content = String(repeating: "\u{E9}", count: count)
            XCTAssertEqual(resolvedLink(content), shippedSurface("[" + content + "]: /u\n\n[" + content + "]"))
        }
    }
}
