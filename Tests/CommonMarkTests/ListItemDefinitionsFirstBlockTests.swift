/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list item whose first block is a paragraph of only link reference or inline-attribute definitions.
///
/// A definition is a block of the item, so the item does not begin with a blank line (List items) and blank lines
/// after the definitions keep it open for a following line indented to its content column. A blank line between the
/// definitions and that line's block makes the list loose (Lists).
@Suite("List item whose first block is only definitions")
struct ListItemDefinitionsFirstBlockTests {

    static let options: MarkdownDocument.ParseOptions = [.footnotes, .tables, .strikethrough, .tasklist, .attributes]

    @Test(
        "a block after two blank lines belongs to the item",
        arguments: [
            ("- [r]: /u\n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
            ("- ^[r]: k: v\n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
            ("- [r]: /u\n  [s]: /v\n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
            ("- a\n- [r]: /u\n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "a"
                    item
                      paragraph
                        text "b"

                """),
            ("> - [r]: /u\n>\n>\n>   b\n", """
                document
                  block_quote
                    list bullet '-' loose
                      item
                        paragraph
                          text "b"

                """),
            ("1. [r]: /u\n\n\n   b\n", """
                document
                  list ordered start=1 delim=period loose
                    item
                      paragraph
                        text "b"

                """),
            ("- a\n  - [r]: /u\n\n\n    b\n", """
                document
                  list bullet '-' tight
                    item
                      paragraph
                        text "a"
                      list bullet '-' loose
                        item
                          paragraph
                            text "b"

                """),
            ("-\n  [r]: /u\n\n\n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
            ("- [r]: /u\n \n \n  b\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
            ("- [r]: /u\n\t\n\n\tb\n", """
                document
                  list bullet '-' loose
                    item
                      paragraph
                        text "b"

                """),
        ]
    )
    func blockAfterTwoBlankLines(_ markdown: String, _ expected: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == expected, "\(markdown.debugDescription)")
    }

    @Test("a block after one blank line belongs to the item")
    func blockAfterOneBlankLine() {
        #expect(TreeDump.dump("- [r]: /u\n\n  b\n", options: Self.options) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("a line continuing the definitions' paragraph leaves the list tight")
    func continuationLineIsTight() {
        #expect(TreeDump.dump("- [r]: /u\n  b\n", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("a following item after two blank lines loosens the list")
    func followingItemAfterTwoBlankLines() {
        #expect(TreeDump.dump("- [r]: /u\n\n\n- b\n", options: Self.options) == """
            document
              list bullet '-' loose
                item
                item
                  paragraph
                    text "b"

            """)
    }

    @Test(
        "definitions as the item's only content leave the list tight",
        arguments: ["- [r]: /u\n", "- [r]: /u\n\n", "- [r]: /u\n\n\n", "- ^[r]: k: v\n\n\n"]
    )
    func definitionsOnly(_ markdown: String) {
        #expect(TreeDump.dump(markdown, options: Self.options) == """
            document
              list bullet '-' tight
                item

            """, "\(markdown.debugDescription)")
    }

    @Test("an unindented line after the blank lines follows the list")
    func unindentedLineFollowsList() {
        #expect(TreeDump.dump("- [r]: /u\n\n\nb\n", options: Self.options) == """
            document
              list bullet '-' tight
                item
              paragraph
                text "b"

            """)
    }
}
