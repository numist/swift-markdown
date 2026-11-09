/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A cell's content may include a pipe escaped as `\|` (Tables (extension)). The backslash is part of the cell but not
/// of its text, and every other byte keeps its own source column.
@Suite("Source ranges around an escaped pipe in a table")
struct TablePipeEscapeSourceRangeTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func textAfterEscapedPipeEndsAtItsLastByte() {
        #expect(surface("| f\\|a |\n|-|") == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:9
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:7
                    text "f|a" @1:3-1:7

            """)
    }

    @Test func textAfterTwoEscapedPipesEndsAtItsLastByte() {
        #expect(surface("| a\\|b\\|c |\n|-|") == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:12
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:10
                    text "a|b|c" @1:3-1:10

            """)
    }

    @Test func textEndingInEscapedPipeEndsAfterThePipe() {
        #expect(surface("| a\\| |\n|-|") == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:8
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:6
                    text "a|" @1:3-1:6

            """)
    }

    @Test func emphasisAfterEscapedPipeKeepsItsColumns() {
        #expect(surface("| \\|*a* |\n|-|") == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:10
                  table_cell align=none colspan=1 rowspan=1 @1:3-1:8
                    text "|" @1:4-1:5
                    emph @1:5-1:8
                      text "a" @1:6-1:7

            """)
    }
}
