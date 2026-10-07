/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A bracket whose caret is backslash-escaped, `[\^…]` or `![\^…]`, is not a footnote reference; across a
/// soft line break it stays literal text on both lines.
@Suite("Escaped-caret footnote-shaped bracket across a soft line break")
struct EscapedCaretFootnoteCrossLineLiteralTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink, .footnotes]

    private func surface(_ bytes: [UInt8]) -> String {
        TreeDump.dump(String(decoding: bytes, as: UTF8.self), options: Self.options)
    }

    @Test func testEscapedCaretImageForm() {
        let bytes: [UInt8] = [0x21, 0x5b, 0x5c, 0x5e, 0xdf, 0xb9, 0x0a, 0xe0, 0x5d]
        #expect(surface(bytes) == """
            document
              paragraph
                text "![^\u{07F9}"
                softbreak
                text "\u{FFFD}]"

            """)
    }

    @Test func testEscapedCaretFourByteScalar() {
        let bytes: [UInt8] = [0x5b, 0x5c, 0x5e, 0xf0, 0x9f, 0x98, 0x80, 0x0a, 0xe0, 0x5d]
        #expect(surface(bytes) == """
            document
              paragraph
                text "[^\u{1F600}"
                softbreak
                text "\u{FFFD}]"

            """)
    }
}
