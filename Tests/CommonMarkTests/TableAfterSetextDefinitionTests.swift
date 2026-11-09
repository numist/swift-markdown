/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A block-quoted link reference definition followed by `===`, then a table. As under Link reference definitions,
/// `===` follows no paragraph content, so it is paragraph text rather than a setext heading underline; the table
/// takes its header row from that paragraph's last line (Tables (extension)).
@Suite("Table after a definition-only setext paragraph")
struct TableAfterSetextDefinitionTests {

    private let source = "> [a]: /u\n> ===\n> a|b\n> -|-\n"

    @Test("the underline stays a paragraph before the table")
    func underlineParagraphBeforeTable() {
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                paragraph
                  text "==="
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
    }

    @Test("a definition spanning two quoted lines leaves the underline before the table",
          arguments: [[], [.sourcePosition]] as [MarkdownDocument.ParseOptions])
    func multiLineDefinitionBeforeTable(positions: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("> [a]:\n> u\n> ===\n> b|c\n> -|-\n", options: positions.union(.tables)) == """
            document
              block_quote
                paragraph
                  text "==="
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "b"
                    table_cell align=none colspan=1 rowspan=1
                      text "c"

            """)
    }

    /// The `=` line cannot underline a paragraph holding only a link reference definition (Setext headings), so
    /// it stays paragraph text, and the delimiter row `-|` makes it the header row of a table starting on line 3.
    @Test("a table whose header row follows a link reference definition starts at the header row")
    func tableAfterDefinitionStartsAtHeaderRow() {
        #expect(TreeDump.dump("[b\n ]:o\n=\n-|\na", options: [.sourcePosition, .tables], sourceRanges: true) == """
            document @1:1-5:2
              table @3:1-5:2
                table_header @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:2
                    text "=" @3:1-3:2
                table_row @5:1-5:2
                  table_cell align=none colspan=1 rowspan=1 @5:1-5:2
                    text "a" @5:1-5:2

            """)
    }

    @Test("without tables, the underline and table lines are one paragraph")
    func oneParagraphWithoutTables() {
        #expect(TreeDump.dump(source, options: []) == """
            document
              block_quote
                paragraph
                  text "==="
                  softbreak
                  text "a|b"
                  softbreak
                  text "-|-"

            """)
    }
}
