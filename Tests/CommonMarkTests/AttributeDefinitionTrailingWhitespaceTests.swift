/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An attribute definition's value is cleaned like a link destination (cmark's `cmark_clean_attributes`):
/// trimmed even when more paragraph content follows it, with escapes and entities decoded.
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

    /// A whitespace-only value line can't form an empty value: the separator skip crosses one line end, so
    /// the value is the next line's content.
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

    /// Flag-OFF shares the link destination's spec-correct single pass: `\&` escapes the `&`, so `amp;` stays literal.
    @Test
    func testEscapeBeforeEntityWithoutBugCompatibility() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:\\&amp; \nx", options: Self.options) == """
            document
              paragraph
                attribute "&amp;"
              paragraph
                text "x"

            """)
    }

    /// The trim is not a cmark quirk, so the flag-OFF deliverable trims too.
    @Test
    func testTrimmedWithoutBugCompatibility() {
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

    /// Control: a definition that isn't at the start of a paragraph is never formed, so its line stays literal.
    @Test
    func testLastLineControl() {
        #expect(TreeDump.dump("^[][$]\n^[$]:l \n", options: Self.options) == """
            document
              paragraph
                text "^[][$]"
                softbreak
                text "^[$]:l"

            """)
    }
}
