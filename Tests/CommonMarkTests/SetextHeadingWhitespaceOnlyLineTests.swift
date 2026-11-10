/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Each line of a setext heading holds a non-whitespace character (Setext headings), and line tabulations and form
/// feeds are whitespace, which keep a line from being blank (Characters and lines). A paragraph with a line of only
/// whitespace is no heading, so a `=` line continues it and a `-` line that is a thematic break interrupts it.
@Suite("Setext underlines after a line of only whitespace")
struct SetextHeadingWhitespaceOnlyLineTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = [.sourcePosition]) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("a paragraph of only whitespace before a thematic break")
    func whitespaceOnlyParagraph() {
        #expect(tree("\u{0B}\n---\n") == """
            document @1:1-3:1
              paragraph @1:1-1:1
              thematic_break @2:1-2:4

            """)
    }

    @Test("a paragraph of only whitespace before a thematic break in a block quote")
    func whitespaceOnlyParagraphInBlockQuote() {
        #expect(tree("> \u{0B}\n> \u{0C}\n> ---\n") == """
            document @1:1-4:1
              block_quote @1:1-3:6
                paragraph @1:3-1:3
                thematic_break @3:3-3:6

            """)
    }

    @Test("a paragraph of only whitespace before a thematic break in a list item")
    func whitespaceOnlyParagraphInListItem() {
        #expect(tree("- \u{0B}\n  ---\n") == """
            document @1:1-3:1
              list bullet '-' tight @1:1-2:6
                item @1:1-2:6
                  paragraph @1:3-1:3
                  thematic_break @2:3-2:6

            """)
    }

    @Test("a `=` line continues a paragraph whose second line is only whitespace")
    func equalsAfterWhitespaceOnlyLine() {
        #expect(tree("a\n\u{0B}\n===\n") == """
            document @1:1-4:1
              paragraph @1:1-3:4
                text "a" @1:1-1:2
                softbreak @-
                text "\\u{B}" @2:1-2:2
                softbreak @-
                text "===" @3:1-3:4

            """)
    }

    @Test("a thematic break interrupts a paragraph whose second line is only whitespace")
    func thematicBreakAfterWhitespaceOnlyLine() {
        #expect(tree("a\n\u{0C}\n---\n") == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "a" @1:1-1:2
              thematic_break @3:1-3:4

            """)
    }

    @Test("a `=` line continues a paragraph whose first line is only whitespace")
    func equalsAfterLeadingWhitespaceOnlyLine() {
        #expect(tree("\u{0B}\na\n===\n") == """
            document @1:1-4:1
              paragraph @2:1-3:4
                text "a" @2:1-2:2
                softbreak @-
                text "===" @3:1-3:4

            """)
    }

    @Test("a `=` line continues a paragraph with a line of only whitespace after its definitions")
    func equalsAfterDefinitionAndWhitespaceOnlyLine() {
        #expect(tree("[a]: /u\n\u{0B}\nb\n===\n") == """
            document @1:1-5:1
              paragraph @3:1-4:4
                text "b" @3:1-3:2
                softbreak @-
                text "===" @4:1-4:4

            """)
    }

    @Test("a `-` line is a table's delimiter row after a line of only whitespace")
    func delimiterRowAfterWhitespaceOnlyLine() {
        #expect(tree("\u{0B}\n-\n", options: [.tables, .sourcePosition]) == """
            document @1:1-3:1
              table @1:1-2:2
                table_header @1:1-1:1
                  table_cell align=none colspan=1 rowspan=1 @1:1-1:1

            """)
    }
}
