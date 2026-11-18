/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Attribute definition value trimming")
struct AttributeDefinitionTrailingWhitespaceTests {
    private static let options: MarkdownDocument.ParseOptions = [.attributes, .sourcePosition]

    @Test
    func topLevelAfterBlankThenNULLine() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:l \n\u{0}", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "\u{FFFD}"

            """)
    }

    @Test
    func trailingTab() {
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
    func blockQuote() {
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
    func twoTrailingSpaces() {
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
    func interiorSpacesKept() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:a b \nx", options: Self.options) == """
            document
              paragraph
                attribute "a b"
              paragraph
                text "x"

            """)
    }

    @Test
    func followedByAnotherDefinition() {
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
    func crlf() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:l \r\nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "x"

            """)
    }

    // Whitespace after the `:` may include one line ending, as in a link reference definition.
    @Test
    func whitespaceOnlyValueLineTakesNextLine() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]: \t \nx \nz", options: Self.options) == """
            document
              paragraph
                attribute "x"
              paragraph
                text "z"

            """)
    }

    @Test
    func leadingSpaceAfterColon() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]: l \nx", options: Self.options) == """
            document
              paragraph
                attribute "l"
              paragraph
                text "x"

            """)
    }

    @Test
    func escapesAndEntitiesDecoded() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:a\\*&amp;b\nx", options: Self.options) == """
            document
              paragraph
                attribute "a*&b"
              paragraph
                text "x"

            """)
    }

    @Test
    func escapeBeforeEntity() {
        #expect(TreeDump.dump("^[][$]\n\n^[$]:\\&amp; \nx", options: Self.options) == """
            document
              paragraph
                attribute "&amp;"
              paragraph
                text "x"

            """)
    }

    @Test
    func trimmedBeforeLazyContinuationLine() {
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

    @Test
    func definitionAfterParagraphTextIsLiteral() {
        #expect(TreeDump.dump("^[][$]\n^[$]:l \n", options: Self.options) == """
            document
              paragraph
                text "^[]"
                softbreak
                text "^[$]:l"

            """)
    }
}
