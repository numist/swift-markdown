/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Footnote continuation indent after a partially consumed tab")
struct FootnoteContinuationIndentAfterTabTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    /// A footnote definition's continuation indent (four columns) is likewise measured from the column
    /// the outer prefix reached: a tab left partially consumed by `>` or by a `- ` item's content indent
    /// spans only to its tab stop, so ` x` after it is three columns in and the definition closes.
    @Test func testFootnoteContinuationIndentAfterPartiallyConsumedTab() {
        #expect(TreeDump.dump("[^a]\n\n> [^a]: ```\n>\t x", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              block_quote
                paragraph
                  text "x"
              footnote_definition "a"
                code_block "" ""

            """)
        #expect(TreeDump.dump("[^a]\n\n- [^a]: ```\n \t x", options: Self.options) == """
            document
              paragraph
                footnote_reference "1"
              list bullet '-' tight
                item
                  paragraph
                    text "x"
              footnote_definition "a"
                code_block "" ""

            """)
    }
}
