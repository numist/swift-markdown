/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A table header line inside a block quote whose `>` is followed by a tab. The block quote marker consumes one
/// column of the tab (Tabs) and the remaining columns become spaces, so the header line's content is expanded rather
/// than a slice of the source.
@Suite("Table header from a tab-expanded line")
struct TabExpandedTableHeaderTests {

    private let source = ">\ta|b\n>\t-|-\n"

    @Test("a tab-expanded header line opens a table")
    func opensTable() {
        #expect(TreeDump.dump(source, options: [.tables]) == """
            document
              block_quote
                table
                  table_header
                    table_cell align=none colspan=1 rowspan=1
                      text "a"
                    table_cell align=none colspan=1 rowspan=1
                      text "b"

            """)
    }

    @Test("without tables, the header and delimiter lines stay a paragraph")
    func staysParagraphWithoutTables() {
        #expect(TreeDump.dump(source, options: []) == """
            document
              block_quote
                paragraph
                  text "a|b"
                  softbreak
                  text "-|-"

            """)
    }
}
