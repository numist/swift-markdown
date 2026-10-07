/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of paragraph content that `.cmarkBugCompatibility` copies into a buffer instead of borrowing from
/// the source: a definition-only paragraph that a setext underline leaves open, and a task item's line that cmark's
/// three-byte checkbox advance leaves starting inside a NUL's U+FFFD. Every byte of the buffer keeps the source
/// byte it came from, so the nodes built from it are placed on their source lines.
///
/// Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of materialized paragraph content")
struct MaterializedContentSourceRangeTests {

    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans, .cmarkBugCompatibility]

    private static let specOpts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = Self.opts) -> String {
        CmarkTreeDump.dump(source, options: options, sourceRanges: true)
    }

    /// The setext underline `=` resolves the definition `[b\n ]:o` and stays in the paragraph, and the delimiter row
    /// makes it a table's header. The header, its cell and text sit on line 3, the body row on line 5. cmark-gfm
    /// places the header on line 1 (`@1:1-1:2`), the paragraph's first line, because it counts columns in the
    /// paragraph text that is left once the definition is resolved.
    @Test("a table from a definition-only paragraph left open by a setext underline")
    func tableAfterResolvedDefinition() {
        #expect(tree("[b\n ]:o\n=\n-|\na") == """
            document @1:1-5:2
              table @1:1-5:2
                table_header @3:1-3:2
                  table_cell align=none colspan=1 rowspan=1 @3:1-3:2
                    text "=" @3:1-3:2
                table_row @5:1-5:2
                  table_cell align=none colspan=1 rowspan=1 @5:1-5:2
                    text "a" @5:1-5:2

            """)
    }

    /// cmark's checkbox scan matches `2\0 [x]` on the item's second line and advances three bytes from the `2`,
    /// counting the NUL as its three-byte U+FFFD, so the paragraph starts with one leftover byte of it, replaced by a
    /// U+FFFD that stands for the NUL at column 4. The text runs from there to the space before `*u*` at column 9;
    /// cmark-gfm counts the NUL as three columns, placing it at `@2:6-2:12` and the emphasis at `@2:12-2:15`.
    @Test("a task item line that starts inside a NUL's replacement")
    func lineStartingInsideNULReplacement() {
        #expect(tree("+\n  2\u{0} [x] *u*") == """
            document @1:1-2:13
              list bullet '+' tight @1:1-2:13
                tasklist checked @1:1-2:13
                  paragraph @2:4-2:13
                    text "\u{FFFD} [x] " @2:4-2:10
                    emph @2:10-2:13
                      text "u" @2:11-2:12

            """)
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
