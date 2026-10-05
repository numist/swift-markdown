/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of a GFM table nested in a container: a block quote, a list item, both, a container whose prefix is
/// a tab, and a table whose header is a lazy continuation line.
///
/// A nested table's lines aren't contiguous in the source (each carries its container's prefix), so the table is
/// built from a copy of its lines, and every row, cell and cell inline is placed back on its source line through that
/// copy's map to the source. Columns are 1-based UTF-8 byte offsets and each end is half-open. Unless a test says
/// otherwise, every range equals cmark-gfm's.
///
/// A short row's padded filler cell has no source text, so it has no range here, and cmark-gfm gives it column 0,
/// which swift-markdown also reads as no range.
@Suite("Source ranges of tables nested in containers")
struct ContainerTableSourceRangeTests {

    /// The shipped option set: what the Markdown wrapper enables, without `.cmarkBugCompatibility`.
    static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String) throws -> String {
        try CmarkTreeDump.dump(source, options: Self.opts, sourceRanges: true)
    }

    @Test("a table in a list item")
    func listItem() throws {
        #expect(try tree("- b|c\n  -|-\n  d|e") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  table @1:3-3:6
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "b" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "c" @1:5-1:6
                    table_row @3:3-3:6
                      table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                        text "d" @3:3-3:4
                      table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                        text "e" @3:5-3:6

            """)
    }

    @Test("a table in a block quote")
    func blockQuote() throws {
        #expect(try tree("> b|c\n> -|-\n> d|e") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                table @1:3-3:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "e" @3:5-3:6

            """)
    }

    @Test("a table in a list item in a block quote")
    func nestedContainers() throws {
        #expect(try tree("> - b|c\n>   -|-\n>   d|e") == """
            document @1:1-3:8
              block_quote @1:1-3:8
                list bullet '-' tight @1:3-3:8
                  item @1:3-3:8
                    table @1:5-3:8
                      table_header @1:5-1:8
                        table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                          text "b" @1:5-1:6
                        table_cell align=none colspan=1 rowspan=1 @1:7-1:8
                          text "c" @1:7-1:8
                      table_row @3:5-3:8
                        table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                          text "d" @3:5-3:6
                        table_cell align=none colspan=1 rowspan=1 @3:7-3:8
                          text "e" @3:7-3:8

            """)
    }

    /// The `>` prefix and the tab after it are each one byte, so every row's content starts at byte column 3.
    @Test("a table in a block quote whose prefix ends in a tab")
    func tabAfterBlockQuoteMarker() throws {
        #expect(try tree(">\tb|c\n>\t-|-\n>\td|e") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                table @1:3-3:6
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "e" @3:5-3:6

            """)
    }

    /// The body row `\td|e` is indented by one tab byte, so `d` is at byte column 2 and the row, its cells and their
    /// text start one column left of cmark-gfm's, which counts the tab as the two columns of indent it stands for
    /// (`@3:3-3:5` for the row, `@3:3-3:4` and `@3:5-3:6` for the cells and their text). The row's end is the line's
    /// end in both.
    @Test("a table in a list item whose continuation lines are indented by a tab")
    func tabIndentedListItem() throws {
        #expect(try tree("-\tb|c\n\t-|-\n\td|e") == """
            document @1:1-3:5
              list bullet '-' tight @1:1-3:5
                item @1:1-3:5
                  table @1:3-3:5
                    table_header @1:3-1:6
                      table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                        text "b" @1:3-1:4
                      table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                        text "c" @1:5-1:6
                    table_row @3:2-3:5
                      table_cell align=none colspan=1 rowspan=1 @3:2-3:3
                        text "d" @3:2-3:3
                      table_cell align=none colspan=1 rowspan=1 @3:4-3:5
                        text "e" @3:4-3:5

            """)
    }

    /// The header `b|c` is a lazy continuation of the block quote's paragraph, so it sits at the start of line 2.
    /// cmark-gfm places the table and its header on the paragraph's first line instead, at the columns of the header's
    /// bytes within the joined paragraph text (`@1:3-3:6` for the table, `@1:3-1:8` for the header row, `@1:5-1:6` and
    /// `@1:7-1:8` for the cells and their text), and gives the paragraph `a` no range.
    @Test("a table in a block quote whose header is a lazy continuation line")
    func lazyHeader() throws {
        #expect(try tree("> a\nb|c\n> -|-") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
                table @2:1-3:6
                  table_header @2:1-2:4
                    table_cell align=none colspan=1 rowspan=1 @2:1-2:2
                      text "b" @2:1-2:2
                    table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                      text "c" @2:3-2:4

            """)
    }

    /// The paragraph line before the header becomes its own paragraph. cmark-gfm places the table and its header on
    /// that paragraph's line, at the columns of the header's bytes within the joined paragraph text (`@1:3-3:6` for the
    /// table, `@1:3-1:8` for the header row, `@1:5-1:6` and `@1:7-1:8` for the cells and their text), and gives the
    /// paragraph `a` no range.
    @Test("a table in a list item after a paragraph line")
    func listItemWithPrecedingParagraph() throws {
        #expect(try tree("- a\n  b|c\n  -|-") == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  table @2:3-3:6
                    table_header @2:3-2:6
                      table_cell align=none colspan=1 rowspan=1 @2:3-2:4
                        text "b" @2:3-2:4
                      table_cell align=none colspan=1 rowspan=1 @2:5-2:6
                        text "c" @2:5-2:6

            """)
    }

    /// The cell spans its source bytes `b\|x`. Its text `b|x` drops the backslash, so the text's range starts with the
    /// cell's and is one byte shorter, as in cmark-gfm.
    @Test("a table in a block quote with an escaped pipe in a cell")
    func escapedPipe() throws {
        #expect(try tree("> b\\|x|c\n> -|-") == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:9
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:7
                      text "b|x" @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:8-1:9
                      text "c" @1:8-1:9

            """)
    }

    /// The NUL is one source byte, so the U+FFFD that replaces it in the text maps back onto that byte.
    @Test("a table in a block quote with a NUL in a cell")
    func nulInCell() throws {
        #expect(try tree("> b\u{0}|c\n> -|-") == """
            document @1:1-2:6
              block_quote @1:1-2:6
                table @1:3-2:6
                  table_header @1:3-1:7
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:5
                      text "b\u{FFFD}" @1:3-1:5
                    table_cell align=none colspan=1 rowspan=1 @1:6-1:7
                      text "c" @1:6-1:7

            """)
    }

    @Test("a short row in a block-quoted table pads a filler cell with no range")
    func shortRow() throws {
        #expect(try tree("> b|c\n> -|-\n> d|") == """
            document @1:1-3:5
              block_quote @1:1-3:5
                table @1:3-3:5
                  table_header @1:3-1:6
                    table_cell align=none colspan=1 rowspan=1 @1:3-1:4
                      text "b" @1:3-1:4
                    table_cell align=none colspan=1 rowspan=1 @1:5-1:6
                      text "c" @1:5-1:6
                  table_row @3:3-3:5
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "d" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @-

            """)
    }
}
