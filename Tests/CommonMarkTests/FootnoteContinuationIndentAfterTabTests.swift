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

    // The partly consumed tab reaches only its tab stop (Tabs), so `x` is three columns past the container's content,
    // short of the four a footnote definition's continuation line needs.
    @Test func footnoteContinuationIndentAfterPartiallyConsumedTab() {
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
