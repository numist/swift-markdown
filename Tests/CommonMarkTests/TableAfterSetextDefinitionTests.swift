/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A block-quoted paragraph made of a link reference definition followed by a setext underline `===`, then a table.
/// cmark resolves the definition when it scans the underline, finds no content left, and keeps the underline as
/// paragraph text (blocks.c, `resolve_reference_link_definitions`); the table then splits off that paragraph. The
/// rewrite drops the empty paragraph and starts a new one at the underline, which gives cmark's tree. Source positions are off unless a test runs both modes.
@Suite("Table after a definition-only setext paragraph")
struct TableAfterSetextDefinitionTests {

    private let source = "> [a]: /u\n> ===\n> a|b\n> -|-\n"

    @Test("the underline stays a paragraph before the table")
    func underlineParagraphBeforeTable() {
        #expect(CmarkTreeDump.dump(source, options: [.tables]) == """
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
        #expect(CmarkTreeDump.dump("> [a]:\n> u\n> ===\n> b|c\n> -|-\n", options: positions.union(.tables)) == """
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

    @Test("without tables, the underline and table lines are one paragraph")
    func oneParagraphWithoutTables() {
        #expect(CmarkTreeDump.dump(source, options: []) == """
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
