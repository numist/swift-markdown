/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An attribute definition's value is trimmed, even when more paragraph content follows it, and its backslash
/// escapes and entity references are decoded.
@Suite("Attribute definition value trimming")
struct AttributeDefinitionTrailingWhitespaceTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink]

    @Test
    func testTopLevelAfterBlankThenNULLine() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:l \n\u{0}", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "\u{FFFD}"

            """)
    }

    @Test
    func testTrailingTab() {
        #expect(TreeDump.dump("^[][$]\n- ^[$]:l\t\n\u{0}", options: Self.options) == """
            document
              paragraph
                attribute "l"
              list bullet '-' tight
                item
                  paragraph
                    text "\u{FFFD}"

            """)
    }

    @Test
    func testBlockQuote() {
        #expect(TreeDump.dump("^[][$]\n> ^[$]:l \n\u{0}", options: Self.options) == """
            document
              paragraph
                attribute "l"
              block_quote
                paragraph
                  text "\u{FFFD}"

            """)
    }

    @Test
    func testTwoTrailingSpaces() {
        #expect(TreeDump.dump("^[][$]\n- ^[$]:l  \n\u{0}", options: Self.options) == """
            document
              paragraph
                attribute "l"
              list bullet '-' tight
                item
                  paragraph
                    text "\u{FFFD}"

            """)
    }

    @Test
    func testInteriorSpacesKept() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:a b \nx", options: Self.options) == """
            document
              paragraph
                attribute "a b"
              paragraph
                text "x"

            """)
    }

    @Test
    func testFollowedByAnotherDefinition() {
        #expect(TreeDump.dump("^[][$]^[][y]\n\n^[$]:l \n^[y]:m \nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
                attribute "m"
              paragraph
                text "x"

            """)
    }

    @Test
    func testCRLF() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:l \r\nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "x"

            """)
    }

    /// The whitespace after the `:` may include one line ending, so a whitespace-only value line takes its value
    /// from the next line.
    @Test
    func testWhitespaceOnlyValueLineTakesNextLine() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]: \t \nx \nz", options: Self.options) == """
            document
              paragraph
                attribute "x"
              paragraph
                text "z"

            """)
    }

    @Test
    func testLeadingSpaceAfterColon() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]: l \nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "x"

            """)
    }

    @Test
    func testEscapesAndEntitiesDecoded() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:a\\*&amp;b\nx", options: Self.options) == """
            document
              paragraph
                attribute "a*&b"
              paragraph
                text "x"

            """)
    }

    /// `\&` escapes the `&`, so `amp;` is literal.
    @Test
    func testEscapeBeforeEntity() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:\\&amp; \nx", options: Self.options) == """
            document
              paragraph
                attribute "&amp;"
              paragraph
                text "x"

            """)
    }

    @Test
    func testTrimmedBeforeLazyContinuationLine() {
        #expect(TreeDump.dump("^[][$]\n- ^[$]:l \nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
              list bullet '-' tight
                item
                  paragraph
                    text "x"

            """)
    }

    /// A definition that doesn't start a paragraph is paragraph text.
    @Test
    func testDefinitionAfterParagraphTextIsLiteral() {
        #expect(TreeDump.dump("^[][$]\n^[$]:l \n", options: Self.options) == """
            document
              paragraph
                text "^[][$]"
                softbreak
                text "^[$]:l"

            """)
    }
}
