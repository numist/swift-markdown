/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of materialized paragraph content")
struct MaterializedContentSourceRangeTests {

    private static let specOpts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    /// The `=` line cannot underline a paragraph holding only a link reference definition (Setext headings), so
    /// it stays paragraph text, and the delimiter row `-|` makes it the header row of a table starting on line 3.
    @Test("a table whose header row follows a link reference definition starts at the header row")
    func tableAfterResolvedDefinition() {
        #expect(tree("[b\n ]:o\n=\n-|\na", options: Self.specOpts) == """
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

    /// A task list item marker must begin the paragraph (Task list items (extension)), so the `[x]` after `2` is
    /// text. The NUL, replaced by U+FFFD, spans its one source byte.
    @Test("a list item line holding a NUL before a checkbox")
    func lineHoldingNULBeforeCheckbox() {
        #expect(tree("+\n  2\u{0} [x] *u*", options: Self.specOpts) == """
            document @1:1-2:13
              list bullet '+' tight @1:1-2:13
                item @1:1-2:13
                  paragraph @2:3-2:13
                    text "2\u{FFFD} [x] " @2:3-2:10
                    emph @2:10-2:13
                      text "u" @2:11-2:12

            """)
    }
}
