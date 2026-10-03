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
/// paragraph text (blocks.c, `resolve_reference_link_definitions`); the table then splits off that paragraph. With
/// `.cmarkBugCompatibility` the rewrite reproduces that structure, here with source positions off.
@Suite("Table after a definition-only setext paragraph")
struct TableAfterSetextDefinitionTests {

    private let source = "> [a]: /u\n> ===\n> a|b\n> -|-\n"

    @Test("the underline stays a paragraph before the table")
    func underlineParagraphBeforeTable() throws {
        #expect(try CmarkTreeDump.dump(source, options: [.tables, .cmarkBugCompatibility]) == """
            document
              block_quote
                paragraph
                  text "==="
                table
                  table_header
                    table_cell colspan=1 rowspan=1
                      text "a"
                    table_cell colspan=1 rowspan=1
                      text "b"

            """)
    }

    @Test("without tables, the underline and table lines are one paragraph")
    func oneParagraphWithoutTables() throws {
        #expect(try CmarkTreeDump.dump(source, options: [.cmarkBugCompatibility]) == """
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
