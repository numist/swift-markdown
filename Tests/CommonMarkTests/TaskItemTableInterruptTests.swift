/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A task list item whose first paragraph is followed by table lines: the table splits the paragraph, and the item
/// keeps its checkbox only when its first block is a paragraph beginning with a task list item marker (GFM "Tables",
/// "Task list items").
@Suite("Table interrupting a task item paragraph")
struct TaskItemTableInterruptTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .gfmAutolink,
    ]

    @Test func fuzzedArtifactInEveryVariant() {
        #expect(TreeDump.dump("- [x] |\n\u{1}\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "|"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "\\u{1}"

            """)
    }

    @Test func indentedHeaderAndDelimiter() {
        #expect(TreeDump.dump("- [x] a\n  b|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    @Test func lazyHeaderIndentedDelimiter() {
        #expect(TreeDump.dump("- [x] a\nb\n  |-|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    @Test func pipedTableWithBodyRow() {
        #expect(TreeDump.dump("* [x] a\n  |b|\n  |-|\n  |c|", options: Self.options) == """
            document
              list bullet '*' tight
                tasklist checked
                  paragraph
                    text "a"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
                    table_row
                      table_cell align=none colspan=1 rowspan=1
                        text "c"

            """)
    }

    @Test func multiLinePrecedingParagraph() {
        #expect(TreeDump.dump("- [x] a\n  b\n  c|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                    softbreak
                    text "b"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "c"

            """)
    }

    @Test func crlfLineEndings() {
        #expect(TreeDump.dump("- [x] a\r\n  b|\r\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    @Test func tabIndentedHeader() {
        #expect(TreeDump.dump("- [x] a\n\tb|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    /// The split-off paragraph is never finalized in cmark (`try_inserting_table_header_paragraph`), so a
    /// ref-def-shaped remainder after the checkbox stays literal text.
    @Test func refDefShapedPrecedingParagraphStaysText() {
        #expect(TreeDump.dump("- [x] [a]: /u\n  b|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "[a]: /u"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    @Test func nestedTaskItem() {
        #expect(TreeDump.dump("- a\n  - [ ] b\n    c|\n    -|", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                  list bullet '-' tight
                    tasklist unchecked
                      paragraph
                        text "b"
                      table
                        table_header
                          table_cell align=none colspan=1 rowspan=1
                            text "c"

            """)
    }

    /// cmark sets the checked state by `strstr` over the opening line (`open_tasklist_item`); the
    /// spec-correct state comes from the leading token.
    @Test func checkedStateQuirkOnSplitOffLine() {
        #expect(TreeDump.dump("- [ ] a [x]\n  b|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist unchecked
                  paragraph
                    text "a [x]"
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "b"

            """)
    }

    /// cmark strips the checkbox at item open, so the setext scan's ref-def resolution sees `[a]: /u`,
    /// consumes it, and the heading holds only the remaining line.
    @Test func setextHeadingAfterTaskItemRefDef() {
        // `[x] [a]: /u` does not begin with a link reference definition, so it is heading text, and a
        // heading is not the paragraph a task list item must begin with (spec "Task list items (extension)").
        #expect(TreeDump.dump("- [x] [a]: /u\n  b\n  ===", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  heading 1
                    text "[x] [a]: /u"
                    softbreak
                    text "b"

            """)
    }

    /// Nothing but a ref-def precedes the underline, so no heading forms: cmark keeps the paragraph open
    /// and absorbs `===` as text; the spec-correct default redispatches `===` as a new paragraph.
    @Test func setextUnderlineAfterTaskItemRefDefOnly() {
        #expect(TreeDump.dump("- [x] [a]: /u\n  ===", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  heading 1
                    text "[x] [a]: /u"

            """)
    }

    @Test func lazyDelimiterRowStaysParagraph() {
        #expect(TreeDump.dump("- [x] a\nb|c\n-|-", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "a"
                    softbreak
                    text "b|c"
                    softbreak
                    text "-|-"

            """)
    }

    @Test func checkboxAfterBlockQuoteMarkerStaysLiteral() {
        // The item's first paragraph begins with a task list item marker, whatever precedes the list
        // marker on its line (spec "Task list items (extension)").
        #expect(TreeDump.dump("> - [x] a\n>   b|\n>   -|", options: Self.options) == """
            document
              block_quote
                list bullet '-' tight
                  tasklist checked
                    paragraph
                      text "a"
                    table
                      table_header
                        table_cell align=none colspan=1 rowspan=1
                          text "b"

            """)
    }

    @Test func tableIsWholeFirstParagraph() {
        // The header row `[x] |a|` has two cells and the delimiter row one, so no table forms (spec "Tables
        // (extension)") and the paragraph begins with the task list item marker.
        #expect(TreeDump.dump("- [x] |a|\n  |-|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "|a|"
                    softbreak
                    text "|-|"

            """)
    }

    @Test func tableAfterBlankTaskLine() {
        #expect(TreeDump.dump("- [x] \n  a|\n  -|", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"

            """)
    }

    @Test func setextHeadingKeepsCheckbox() {
        // A heading is not the paragraph a task list item must begin with (spec "Task list items (extension)").
        #expect(TreeDump.dump("- [ ] a\n  b\n  ---", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  heading 2
                    text "[ ] a"
                    softbreak
                    text "b"

            """)
    }

    @Test func refDefOnlyTaskItem() {
        // `[x] [a]: /u` does not begin with a link reference definition, so `[a]: /u` is the paragraph's text.
        #expect(TreeDump.dump("- [x] [a]: /u", options: Self.options) == """
            document
              list bullet '-' tight
                tasklist checked
                  paragraph
                    text "[a]: /u"

            """)
    }
}
