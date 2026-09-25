/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A reference-link use whose label exceeds cmark's length cap does not resolve.
///
/// Ground truth is cmark-gfm (flag-ON). The definition `[x y]: /u` is short; the use `[x<spaces>y]` normalizes
/// to the same label, but cmark's refmap lookup (`map.c`) rejects a raw label over 1000 bytes. A 1000-byte
/// label resolves and a 1001-byte one stays literal, for shortcut, collapsed and full references alike.
class LinkLabelLengthCapTests: XCTestCase {
    private func linkCount(_ markdown: String, options: ParseOptions = [.cmarkBugCompatibility]) -> Int {
        Document(parsing: markdown, options: options).debugDescription(options: [])
            .components(separatedBy: "Link destination:").count - 1
    }

    /// A use whose label content is `length` bytes: `x`, then spaces, then `y`.
    private func label(_ length: Int) -> String {
        "[x" + String(repeating: " ", count: length - 2) + "y]"
    }

    func testShortcutAtCapResolves() {
        XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + label(1000)))
    }

    func testShortcutOverCapStaysLiteral() {
        XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + label(1001)))
    }

    func testCollapsedOverCapStaysLiteral() {
        XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + label(1000) + "[]"))
        XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + label(1001) + "[]"))
    }

    func testFullOverCapStaysLiteral() {
        XCTAssertEqual(1, linkCount("[x y]: /u\n\n[t]" + label(1000)))
        XCTAssertEqual(0, linkCount("[x y]: /u\n\n[t]" + label(1001)))
    }

    // MARK: What cmark measures

    /// cmark counts bytes, so a 3-byte `€` weighs 3 toward the 1000-byte lookup cap.
    func testMultibyteShortcutCountsBytes() {
        let definition = "[\u{20AC} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 996) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 997) + "y]"))
    }

    /// A NUL counts as the 3-byte U+FFFD cmark substitutes for it before inline parsing.
    func testNULShortcutCountsReplacementBytes() {
        let definition = "[x \u{0} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 994) + "y]"))
        XCTAssertEqual(0, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 995) + "y]"))
    }

    /// An image's shortcut label is measured from just past `![`.
    func testImageShortcutOverCapStaysLiteral() {
        let imageCount = { (markdown: String) in
            Document(parsing: markdown, options: [.cmarkBugCompatibility]).debugDescription(options: [])
                .components(separatedBy: "Image source:").count - 1
        }
        XCTAssertEqual(1, imageCount("[x y]: /u\n\n!" + label(1000)))
        XCTAssertEqual(0, imageCount("[x y]: /u\n\n!" + label(1001)))
    }

    /// cmark measures its content buffer: each line ending (CRLF included) is one `\n`, and a
    /// continuation line's container prefix and leading whitespace are gone.
    func testMultilineShortcutCountsContentBytes() {
        let spaces = { String(repeating: " ", count: $0) }
        XCTAssertEqual(1, linkCount("[x y]: /u\n\n> [x" + spaces(997) + "\n>    y]"))
        XCTAssertEqual(0, linkCount("[x y]: /u\n\n> [x" + spaces(998) + "\n>    y]"))
        XCTAssertEqual(1, linkCount("[x y]: /u\r\n\r\n[x" + spaces(997) + "\r\ny]"))
        XCTAssertEqual(0, linkCount("[x y]: /u\r\n\r\n[x" + spaces(998) + "\r\ny]"))
    }

    /// A blank full label `[ ]` falls back to the shortcut label, which the cap then measures.
    func testBlankFullLabelFallbackOverCapStaysLiteral() {
        XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + label(1000) + "[ ]"))
        XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + label(1001) + "[ ]"))
    }

    /// A definition whose label is over the cap is not a definition, so nothing resolves against it.
    func testDefinitionOverCapDoesNotRegister() {
        XCTAssertEqual(1, linkCount(label(1000) + ": /u\n\n[x y]"))
        XCTAssertEqual(0, linkCount(label(1001) + ": /u\n\n[x y]"))
    }

    /// 500 two-byte `é` is 1000 bytes (defines and resolves); 501 is 1002 bytes on both sides.
    func testMultibyteDefinitionAndUseCountBytes() {
        let e500 = "[" + String(repeating: "\u{E9}", count: 500) + "]"
        let e501 = "[" + String(repeating: "\u{E9}", count: 501) + "]"
        XCTAssertEqual(1, linkCount(e500 + ": /u\n\n" + e500))
        XCTAssertEqual(0, linkCount(e501 + ": /u\n\n" + e501))
    }

    // MARK: Spec (flag-off): at most 999 characters inside the brackets

    func testSpecShortcutCollapsedAndFullCapAt999Characters() {
        for (use, suffix) in [("", ""), ("", "[]"), ("[t]", "")] {
            XCTAssertEqual(1, linkCount("[x y]: /u\n\n" + use + label(999) + suffix, options: []), "\(use)|\(suffix)")
            XCTAssertEqual(0, linkCount("[x y]: /u\n\n" + use + label(1000) + suffix, options: []), "\(use)|\(suffix)")
        }
    }

    func testSpecDefinitionCapAt999Characters() {
        XCTAssertEqual(1, linkCount(label(999) + ": /u\n\n[x y]", options: []))
        XCTAssertEqual(0, linkCount(label(1000) + ": /u\n\n[x y]", options: []))
    }

    /// The spec counts characters: 999 `é` (1998 bytes) is a label, 1000 is not.
    func testSpecCountsCharactersNotBytes() {
        let e999 = "[" + String(repeating: "\u{E9}", count: 999) + "]"
        let e1000 = "[" + String(repeating: "\u{E9}", count: 1000) + "]"
        XCTAssertEqual(1, linkCount(e999 + ": /u\n\n" + e999, options: []))
        XCTAssertEqual(0, linkCount(e1000 + ": /u\n\n" + e1000, options: []))
        let definition = "[\u{20AC} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 997) + "y]", options: []))
        XCTAssertEqual(0, linkCount(definition + "[\u{20AC}" + String(repeating: " ", count: 998) + "y]", options: []))
    }

    /// A NUL is one character (the U+FFFD it becomes), not three.
    func testSpecCountsNULAsOneCharacter() {
        let definition = "[x \u{0} y]: /u\n\n"
        XCTAssertEqual(1, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 995) + "y]", options: []))
        XCTAssertEqual(0, linkCount(definition + "[x \u{0}" + String(repeating: " ", count: 996) + "y]", options: []))
    }
}
