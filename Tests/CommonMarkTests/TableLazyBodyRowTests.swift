/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Laziness applies only to paragraph continuation text (Block quotes, List items). Once a table opens in a
/// container, a following line without the container's prefix is not a lazy continuation line: it closes
/// the table and the container and starts a new paragraph.
@Suite("Table followed by a line without its container's prefix")
struct TableLazyBodyRowTests {

    // MARK: - Unprefixed lines close the table and its container

    @Test("an unprefixed row closes the table and block quote and starts a paragraph")
    func lazyBodyRowBreaksOut() {
        #expect(TreeDump.dump(">a|b\n>-|-\nc|d", options: .tables) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
              paragraph
                text "c|d"

            """)
    }

    @Test("two unprefixed lines after the delimiter row form one paragraph")
    func twoLazyLinesFormOneParagraph() {
        #expect(TreeDump.dump(">a|b\n>-|-\nc|d\ne|f", options: .tables) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
              paragraph
                text "c|d"
                softbreak
                text "e|f"

            """)
    }

    @Test("unprefixed text without pipes after the delimiter row starts a paragraph")
    func lazyNonTableTextBreaksOut() {
        #expect(TreeDump.dump(">a|b\n>-|-\nxy", options: .tables) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
              paragraph
                text "xy"

            """)
    }

    @Test("a row not indented to a list item's content closes the table and list")
    func lazyBodyRowBreaksOutOfListItem() {
        #expect(TreeDump.dump("- a|b\n  -|-\nc|d", options: .tables) == """
            document
              list bullet '-' tight
                item
                  table
                    table_header
                      table_cell align=none colspan=1 rowspan=1
                        text "a"
                      table_cell align=none colspan=1 rowspan=1
                        text "b"
              paragraph
                text "c|d"

            """)
    }

    // MARK: - Prefixed body rows

    @Test("a prefixed body row stays in the table; a following unprefixed line starts a paragraph")
    func matchedBodyThenLazyBreaksOut() {
        #expect(TreeDump.dump(">a|b\n>-|-\n>c|d\ne|f", options: .tables) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
                  table_row
                    table_cell align=none colspan=1 rowspan=1
                      text "c"
                    table_cell align=none colspan=1 rowspan=1
                      text "d"
              paragraph
                text "e|f"

            """)
    }

    @Test("a prefixed body row is a table body row inside the block quote")
    func prefixedBodyRowStaysInTable() {
        #expect(TreeDump.dump(">a|b\n>-|-\n>c|d", options: .tables) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
                  table_row
                    table_cell align=none colspan=1 rowspan=1
                      text "c"
                    table_cell align=none colspan=1 rowspan=1
                      text "d"

            """)
    }

    @Test("a table outside any container gets its body row")
    func plainTableGetsBodyRow() {
        #expect(TreeDump.dump("a|b\n-|-\nc|d", options: .tables) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "a"
                  table_cell align=none colspan=1 rowspan=1
                    text "b"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "c"
                  table_cell align=none colspan=1 rowspan=1
                    text "d"

            """)
    }
}
