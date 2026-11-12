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
/// feeds are whitespace, which keep a line from being blank (Characters and lines). The heading's lines are the
/// paragraph's lines less its leading definitions, so a line of only whitespace inside a definition's label or title
/// doesn't keep the rest from being a heading. A paragraph whose other lines include one of only whitespace is no
/// heading, so a `=` line continues it and a `-` line that is a thematic break interrupts it.
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

    @Test("a line of only whitespace in a leading definition's title is no heading line")
    func whitespaceOnlyLineInTitle() {
        #expect(tree("[a]: /u \"t\n\u{0B}\nt\"\n[a]\n===\n") == """
            document @1:1-6:1
              heading 1 @4:1-5:4
                link "/u" "t\\n\\u{B}\\nt" @4:1-4:4
                  text "a" @4:2-4:3

            """)
    }

    @Test("a line of only whitespace in a title after the destination's line is no heading line")
    func whitespaceOnlyLineInTitleOnNextLine() {
        #expect(tree("[a]: /u\n\"t\n\u{0C}\nt\"\n[a]\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                link "/u" "t\\n\\u{C}\\nt" @5:1-5:4
                  text "a" @5:2-5:3

            """)
    }

    @Test("a line of only whitespace in a leading definition's label is no heading line")
    func whitespaceOnlyLineInLabel() {
        #expect(tree("[a\n\u{0B}\n]: /u\nb\n===\n") == """
            document @1:1-6:1
              heading 1 @4:1-5:4
                text "b" @4:1-4:2

            """)
    }

    @Test("a line of only whitespace in a leading attribute definition's label is no heading line")
    func whitespaceOnlyLineInAttributeDefinitionLabel() {
        #expect(tree("^[a\n\u{0B}\n]: b\nc\n===\n", options: [.attributes, .sourcePosition]) == """
            document @1:1-6:1
              heading 1 @4:1-5:4
                text "c" @4:1-4:2

            """)
    }

    @Test("a line of only whitespace in a leading definition's title is no heading line in a block quote")
    func whitespaceOnlyLineInTitleInBlockQuote() {
        #expect(tree("> [a]: /u \"t\n> \u{0B}\n> t\"\n> b\n> ===\n") == """
            document @1:1-6:1
              block_quote @1:1-5:6
                heading 1 @4:3-5:6
                  text "b" @4:3-4:4

            """)
    }

    @Test("a `-` underline forms a heading after a definition whose title holds a line of only whitespace")
    func dashUnderlineAfterWhitespaceOnlyLineInTitle() {
        #expect(tree("[a]: /u \"t\n\u{0B}\nt\"\nb\n---\n") == """
            document @1:1-6:1
              heading 2 @4:1-5:4
                text "b" @4:1-4:2

            """)
    }

    @Test("an underline continues a paragraph whose title is still open, and a later one forms a heading once it closes")
    func underlineBeforeAndAfterTitleCloses() {
        #expect(tree("[a]: /u \"t\n\u{0B}\n===\nt\"\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("an underline continues a paragraph whose `'` title is still open, and a later one forms a heading once it closes")
    func underlineBeforeAndAfterSingleQuotedTitleCloses() {
        #expect(tree("[a]: /u 't\n\u{0B}\n===\nt'\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("an underline continues a paragraph whose parenthesized title is still open, and a later one forms a heading once it closes")
    func underlineBeforeAndAfterParenthesizedTitleCloses() {
        #expect(tree("[a]: /u (t\n\u{0B}\n===\nt)\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("an underline continues a paragraph whose label is still open, and a later one forms a heading once it closes")
    func underlineBeforeAndAfterLabelCloses() {
        #expect(tree("[a\n\u{0B}\n===\n]: /u\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("an underline continues a paragraph whose label awaits a destination, which a later line gives")
    func underlineAsDestinationAfterLabel() {
        #expect(tree("[a\n\u{0B}\n]:\n===\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("a title that closes at an escaped quote before an underline ends there, so a line of only whitespace after it is a heading line")
    func titleClosedAtEscapedQuote() {
        #expect(tree("[a]: /u \"t\\\"\n\u{0B}\n===\nx\"\nb\n===\n") == """
            document @1:1-7:1
              paragraph @3:1-6:4
                text "===" @3:1-3:4
                softbreak @-
                text "x\\"" @4:1-4:3
                softbreak @-
                text "b" @5:1-5:2
                softbreak @-
                text "===" @6:1-6:4

            """)
    }

    @Test("a line of only whitespace before a definition that a later underline ends is a heading line")
    func whitespaceOnlyLineBeforeLateDefinition() {
        #expect(tree("\u{0B}\n[a]: /u \"t\n===\nt\"\nb\n===\n") == """
            document @1:1-7:1
              paragraph @5:1-6:4
                text "b" @5:1-5:2
                softbreak @-
                text "===" @6:1-6:4

            """)
    }

    @Test("an underline forms a heading once a title holding a line of only whitespace closes on an indented line")
    func underlineAfterTitleClosesOnIndentedLine() {
        #expect(tree("[a]: /u \"t\n\u{0B}\n===\n  t\"\nb\n===\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:4
                text "b" @5:1-5:2

            """)
    }

    @Test("a closer followed by more text on its line doesn't close a title holding a line of only whitespace, and a later one does")
    func titleClosesPastCloserFollowedByText() {
        #expect(tree("[a]: /u \"t\n\u{0B}\n===\nx\\\" y\n===\nz\"\n[a]\n===\n") == """
            document @1:1-9:1
              heading 1 @7:1-8:4
                link "/u" "t\\n\\u{B}\\n===\\nx\\" y\\n===\\nz" @7:1-7:4
                  text "a" @7:2-7:3

            """)
    }

    @Test("a `=` line continues a paragraph with a line of only whitespace after a definition whose title holds one")
    func equalsAfterWhitespaceOnlyLineAfterTitle() {
        #expect(tree("[a]: /u \"t\n\u{0B}\nt\"\n\u{0C}\n[a]\n===\n") == """
            document @1:1-7:1
              paragraph @5:1-6:4
                link "/u" "t\\n\\u{B}\\nt" @5:1-5:4
                  text "a" @5:2-5:3
                softbreak @-
                text "===" @6:1-6:4

            """)
    }

    @Test("a `=` line continues a paragraph with a line of only whitespace after a definition whose label holds one")
    func equalsAfterWhitespaceOnlyLineAfterLabel() {
        #expect(tree("[a\n\u{0C}\n]: /u\n\u{0B}\nb\n===\n") == """
            document @1:1-7:1
              paragraph @5:1-6:4
                text "b" @5:1-5:2
                softbreak @-
                text "===" @6:1-6:4

            """)
    }

    @Test("a `=` line continues a paragraph whose first line, before its definitions, is only whitespace")
    func equalsAfterWhitespaceOnlyLineBeforeDefinition() {
        #expect(tree("\u{0B}\n[a]: /u\nb\n===\n") == """
            document @1:1-5:1
              paragraph @3:1-4:4
                text "b" @3:1-3:2
                softbreak @-
                text "===" @4:1-4:4

            """)
    }

    @Test("a `=` line continues a paragraph whose line before it is only whitespace, after a definition whose title holds one")
    func equalsAfterWhitespaceOnlyLastLine() {
        #expect(tree("[a]: /u \"t\n\u{0B}\nt\"\nb\n\u{0C}\n===\n") == """
            document @1:1-7:1
              paragraph @4:1-6:4
                text "b" @4:1-4:2
                softbreak @-
                text "\\u{C}" @5:1-5:2
                softbreak @-
                text "===" @6:1-6:4

            """)
    }

    @Test("a `=` line continues a paragraph with a line of only whitespace after a title that closed after an earlier underline")
    func equalsAfterWhitespaceOnlyLineAfterLateTitle() {
        #expect(tree("[a]: /u \"t\n\u{0B}\n===\nt\"\n\u{0C}\n===\n") == """
            document @1:1-7:1
              paragraph @6:1-6:4
                text "===" @6:1-6:4

            """)
    }

    @Test("`=` lines continue a paragraph with a line of only whitespace after its definition across a line with a `]`")
    func equalsAcrossClosingBracketLine() {
        #expect(tree("[a]: /u\n\u{0B}\n===\n]\n===\n") == """
            document @1:1-6:1
              paragraph @3:1-5:4
                text "===" @3:1-3:4
                softbreak @-
                text "]" @4:1-4:2
                softbreak @-
                text "===" @5:1-5:4

            """)
    }

    @Test("`=` lines continue a paragraph without definitions across a line with a double quote")
    func equalsAcrossQuoteLineWithoutDefinitions() {
        #expect(tree("a\n\u{0B}\n===\n\"\n===\n") == """
            document @1:1-6:1
              paragraph @1:1-5:4
                text "a" @1:1-1:2
                softbreak @-
                text "\\u{B}" @2:1-2:2
                softbreak @-
                text "===" @3:1-3:4
                softbreak @-
                text "\\"" @4:1-4:2
                softbreak @-
                text "===" @5:1-5:4

            """)
    }
}
