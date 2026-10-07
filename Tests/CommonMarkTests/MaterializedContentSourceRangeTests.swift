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
        CmarkTreeDump.dump(source, options: options, sourceRanges: true)
    }

    /// The table starts on line 3 with its header row, the first line left once the definition is resolved, where
    /// cmark-gfm starts it on line 1 with the paragraph.
    @Test("without cmark bug compatibility: a definition-only paragraph left open by a setext underline")
    func tableAfterResolvedDefinitionSpecCompliant() {
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

    /// A task list item's checkbox must open its paragraph, so `2\u{0} [x]` leaves an ordinary list item whose text
    /// starts at the `2` and counts the NUL as its one source byte, where cmark-gfm finds a checked checkbox there.
    @Test("without cmark bug compatibility: a list item line holding a NUL before a checkbox")
    func lineHoldingNULSpecCompliant() {
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
